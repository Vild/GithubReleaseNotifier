module cache;

import db;
import vibe.core.core;
import vibe.core.log;
import vibe.inet.url;
import std.net.curl;
import std.array;
import std.datetime;
import std.datetime.systime : Clock;
import std.algorithm : each;

void cacheTask() {
	auto mongo = connectToMongo();
	logInfo("Cache task started...");

	while (true) {
		long currentTime = Clock.currTime.toUnixTime!long;
		foreach (VersionFile file; VersionFile.findRange(["lastUpdated" : ["$lte" : (currentTime - 10 * 60)]])) {
			logInfo("Downloading: %s", file.url);
			try {
				Appender!(ubyte[]) data;
				file.url.byChunk.each!(x => data.put(x));
				file.data = data.data;
				file.lastUpdated = currentTime;
				file.save();
				logInfo("\tDownloaded a total %d bytes.", file.data.length);
			} catch (CurlException ex) {
				logError("\tDownload failed:\n%s", ex);
			}
			yield();
		}
		sleep(30.seconds);
	}
}
