# NewPipeExtractor runs YouTube's player JavaScript through Rhino, which R8 must not strip
# (rules from NewPipeExtractor's README).
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-dontwarn org.mozilla.javascript.tools.**

# Desktop-JDK APIs Rhino references from code paths NewPipeExtractor never takes on Android
# (JavaBeans conversion, the javax.script engine, invokedynamic linking).
-dontwarn java.beans.**
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**

# NewPipeExtractor builds YouTube playlist continuations with protobuf-lite, which reads message
# fields by name through reflection; renamed fields broke playlist import ("Field browseId_ …
# not found").
-keep class org.schabi.newpipe.extractor.services.youtube.protos.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { <fields>; }

# The bridge reports a failure by the exception's class name and the Dart side reads meaning from
# it (isVideoGone: ContentNotAvailableException etc.); renamed, a removed video looked like any
# other failure and fell through to the YouTube app.
-keepnames class org.schabi.newpipe.extractor.exceptions.** { *; }
