package com.shian1000.music_database_app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.Page
import org.schabi.newpipe.extractor.playlist.PlaylistInfo
import org.schabi.newpipe.extractor.playlist.PlaylistInfoItem
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.search.SearchInfo
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubePlaylistLinkHandlerFactory
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeSearchQueryHandlerFactory
import org.schabi.newpipe.extractor.services.youtube.linkHandler.YoutubeStreamLinkHandlerFactory
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.StreamInfoItem

/**
 * Exposes NewPipeExtractor to Dart on the `music_database_app/newpipe` channel
 * (`lib/src/data/youtube_audio.dart`). Extraction does network I/O, so it runs off the main thread.
 */
class NewPipeBridge(val messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "music_database_app/newpipe")
    private val executor = Executors.newSingleThreadExecutor()
    private val mainThread = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
        initOnce()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "audioStreams" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId == null) {
                    result.error("bad_args", "videoId missing", null)
                    return
                }
                runInBackground(result) { audioStreams(videoId) }
            }
            "video" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId == null) {
                    result.error("bad_args", "videoId missing", null)
                    return
                }
                runInBackground(result) { video(videoId) }
            }
            "search" -> {
                val query = call.argument<String>("query")
                if (query == null) {
                    result.error("bad_args", "query missing", null)
                    return
                }
                runInBackground(result) { search(query) }
            }
            "searchPlaylists" -> {
                val query = call.argument<String>("query")
                if (query == null) {
                    result.error("bad_args", "query missing", null)
                    return
                }
                runInBackground(result) { searchPlaylists(query) }
            }
            "playlist" -> {
                val playlistId = call.argument<String>("playlistId")
                if (playlistId == null) {
                    result.error("bad_args", "playlistId missing", null)
                    return
                }
                runInBackground(result) { playlist(playlistId) }
            }
            else -> result.notImplemented()
        }
    }

    private fun runInBackground(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            try {
                val value = work()
                mainThread.post { result.success(value) }
            } catch (e: Exception) {
                mainThread.post {
                    result.error(e.javaClass.simpleName, e.message ?: "$e", null)
                }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun audioStreams(videoId: String): List<Map<String, Any?>> {
        val info = StreamInfo.getInfo(
            ServiceList.YouTube,
            "https://www.youtube.com/watch?v=$videoId",
        )
        return info.audioStreams.map {
            mapOf(
                "url" to it.content,
                "itag" to it.itag,
                "format" to it.format?.name,
                "mimeType" to it.format?.mimeType,
                "bitrate" to it.averageBitrate,
                "delivery" to it.deliveryMethod.name,
            )
        }
    }

    /** Title, channel and length of one video (a link opened with the app). */
    private fun video(videoId: String): Map<String, Any?> {
        val info = StreamInfo.getInfo(
            ServiceList.YouTube,
            "https://www.youtube.com/watch?v=$videoId",
        )
        return mapOf(
            "id" to videoId,
            "title" to info.name,
            "channel" to info.uploaderName,
            "duration" to info.duration,
            "views" to info.viewCount,
        )
    }

    /** Videos only (not channels/playlists), first results page (~20). */
    private fun search(query: String): List<Map<String, Any?>> {
        val youtube = ServiceList.YouTube
        val handler = youtube.searchQHFactory.fromQuery(
            query,
            listOf(YoutubeSearchQueryHandlerFactory.VIDEOS),
            "",
        )
        val links = YoutubeStreamLinkHandlerFactory.getInstance()
        return SearchInfo.getInfo(youtube, handler).relatedItems
            .filterIsInstance<StreamInfoItem>()
            .map {
                mapOf(
                    "id" to links.getId(it.url),
                    "title" to it.name,
                    "channel" to it.uploaderName,
                    // -1 when unknown, e.g. live streams.
                    "duration" to it.duration,
                    "views" to it.viewCount,
                )
            }
    }

    /** Playlists only, first results page. */
    private fun searchPlaylists(query: String): List<Map<String, Any?>> {
        val youtube = ServiceList.YouTube
        val handler = youtube.searchQHFactory.fromQuery(
            query,
            listOf(YoutubeSearchQueryHandlerFactory.PLAYLISTS),
            "",
        )
        val links = YoutubePlaylistLinkHandlerFactory.getInstance()
        return SearchInfo.getInfo(youtube, handler).relatedItems
            .filterIsInstance<PlaylistInfoItem>()
            .map {
                mapOf(
                    "id" to links.getId(it.url),
                    "name" to it.name,
                    "owner" to it.uploaderName,
                    // -1 when unknown.
                    "count" to it.streamCount,
                    "thumbnail" to it.thumbnails.maxByOrNull { t -> t.width }?.url,
                )
            }
    }

    /** Name, owner and every video of a playlist (all pages, at most [MAX_PLAYLIST_VIDEOS]). */
    private fun playlist(playlistId: String): Map<String, Any?> {
        val youtube = ServiceList.YouTube
        val url = "https://www.youtube.com/playlist?list=$playlistId"
        val info = PlaylistInfo.getInfo(youtube, url)
        val items = info.relatedItems.toMutableList()
        var page = info.nextPage
        while (Page.isValid(page) && items.size < MAX_PLAYLIST_VIDEOS) {
            val more = PlaylistInfo.getMoreItems(youtube, url, page)
            items += more.items
            page = more.nextPage
        }
        val links = YoutubeStreamLinkHandlerFactory.getInstance()
        return mapOf(
            "name" to info.name,
            "owner" to info.uploaderName,
            "videos" to items.map {
                mapOf(
                    "id" to links.getId(it.url),
                    "title" to it.name,
                    "channel" to it.uploaderName,
                    "duration" to it.duration,
                    "views" to it.viewCount,
                )
            },
        )
    }

    companion object {
        private const val MAX_PLAYLIST_VIDEOS = 5000
        private var initialized = false

        @Synchronized
        private fun initOnce() {
            if (initialized) return
            NewPipe.init(UrlConnectionDownloader())
            initialized = true
        }
    }
}

/** The HTTP client NewPipeExtractor asks for; plain HttpURLConnection, no extra dependency. */
private class UrlConnectionDownloader : Downloader() {
    override fun execute(request: Request): Response {
        val connection = URL(request.url()).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = request.httpMethod()
            connection.connectTimeout = 15_000
            connection.readTimeout = 20_000
            connection.setRequestProperty("User-Agent", USER_AGENT)
            for ((name, values) in request.headers()) {
                // setRequestProperty for the first value replaces any default (e.g. User-Agent).
                values.forEachIndexed { i, value ->
                    if (i == 0) {
                        connection.setRequestProperty(name, value)
                    } else {
                        connection.addRequestProperty(name, value)
                    }
                }
            }
            val body = request.dataToSend()
            if (body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(body) }
            }
            val code = connection.responseCode
            val stream = if (code >= 400) connection.errorStream else connection.inputStream
            val text = stream?.bufferedReader()?.use { it.readText() }
            val headers = connection.headerFields.filterKeys { it != null }
            return Response(code, connection.responseMessage ?: "", headers, text, connection.url.toString())
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        // A desktop browser UA: the YouTube web pages NewPipeExtractor parses are served for it.
        const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0"
    }
}
