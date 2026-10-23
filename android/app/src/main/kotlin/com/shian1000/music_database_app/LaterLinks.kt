package com.shian1000.music_database_app

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * "Na później": links saved from [LinkChooserActivity] with the person who sent them. Kept here
 * rather than in Dart's local.db because the sheet saves without starting Flutter; Dart reads
 * and changes them over the links channel (`lib/src/data/later_links.dart`).
 */
object LaterLinks {
    private const val PREFS = "later_links"
    private const val PEOPLE = "people"
    private const val LINKS = "links"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun read(context: Context, key: String): MutableList<JSONObject> {
        val raw = prefs(context).getString(key, null) ?: return mutableListOf()
        return try {
            val array = JSONArray(raw)
            MutableList(array.length()) { array.getJSONObject(it) }
        } catch (e: Exception) {
            mutableListOf()
        }
    }

    private fun write(context: Context, key: String, items: List<JSONObject>) {
        prefs(context).edit().putString(key, JSONArray(items).toString()).apply()
    }

    /** People, the one picked most recently first. */
    fun people(context: Context): List<JSONObject> =
        read(context, PEOPLE).sortedByDescending { it.optLong("usedAt") }

    /** Everything, for Dart: `{"people": [...], "links": [...]}`. */
    fun all(context: Context): String = JSONObject()
        .put(PEOPLE, JSONArray(read(context, PEOPLE)))
        .put(LINKS, JSONArray(read(context, LINKS)))
        .toString()

    /** Puts [json] (what [all] gives) in place of everything: a restored backup. */
    fun replaceAll(context: Context, json: String) {
        val all = JSONObject(json)
        val people = all.optJSONArray(PEOPLE) ?: JSONArray()
        val links = all.optJSONArray(LINKS) ?: JSONArray()
        prefs(context).edit()
            .putString(PEOPLE, people.toString())
            .putString(LINKS, links.toString())
            .commit()
    }

    /** The person called [name] (case aside), added when there's none; returns its id. */
    fun addPerson(context: Context, name: String): String {
        val people = read(context, PEOPLE)
        people.firstOrNull { it.optString("name").equals(name, ignoreCase = true) }
            ?.let { return it.getString("id") }
        val id = UUID.randomUUID().toString()
        people.add(JSONObject().put("id", id).put("name", name).put("usedAt", 0L))
        write(context, PEOPLE, people)
        return id
    }

    fun renamePerson(context: Context, id: String, name: String) {
        val people = read(context, PEOPLE)
        people.firstOrNull { it.optString("id") == id }?.put("name", name)
        write(context, PEOPLE, people)
    }

    /** The person and every link from them. */
    fun removePerson(context: Context, id: String) {
        write(context, PEOPLE, read(context, PEOPLE).filter { it.optString("id") != id })
        write(context, LINKS, read(context, LINKS).filter { it.optString("personId") != id })
    }

    fun save(context: Context, url: String, service: String, kind: String, personId: String) {
        val now = System.currentTimeMillis()
        val links = read(context, LINKS)
        // The same link from the same person again only moves it to the top, keeping its id
        // (shared with MusicDatabase once synced).
        val same = links.firstOrNull {
            it.optString("url") == url && it.optString("personId") == personId &&
                !it.has("deletedAt")
        }
        if (same != null) {
            same.put("savedAt", now).put("updatedAt", now).remove("openedAt")
            if (same.has("account")) same.put("dirty", true)
        } else {
            links.add(
                JSONObject()
                    .put("id", UUID.randomUUID().toString())
                    .put("url", url)
                    .put("service", service)
                    .put("kind", kind)
                    .put("personId", personId)
                    .put("savedAt", now),
            )
        }
        write(context, LINKS, links)
        val people = read(context, PEOPLE)
        people.firstOrNull { it.optString("id") == personId }?.put("usedAt", now)
        write(context, PEOPLE, people)
    }

    /** Changes the fields of link [id] given in [fields] (`null` removes one). */
    fun updateLink(context: Context, id: String, fields: Map<String, Any?>) {
        val links = read(context, LINKS)
        val link = links.firstOrNull { it.optString("id") == id } ?: return
        for ((key, value) in fields) {
            if (key == "id") continue
            if (value == null) link.remove(key) else link.put(key, value)
        }
        write(context, LINKS, links)
    }

    /** Stores [link] (with its `id`, from MusicDatabase) in place of the one with its id. */
    fun putLink(context: Context, link: Map<String, Any?>) {
        val id = link["id"] as? String ?: return
        val links = read(context, LINKS).filter { it.optString("id") != id }.toMutableList()
        val json = JSONObject()
        for ((key, value) in link) if (value != null) json.put(key, value)
        links.add(json)
        write(context, LINKS, links)
    }

    fun removeLink(context: Context, id: String) {
        write(context, LINKS, read(context, LINKS).filter { it.optString("id") != id })
    }
}
