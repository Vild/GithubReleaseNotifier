module db.cache;

import db;
import vibe.core.core;
import vibe.core.log;
import vibe.inet.url;
import std.net.curl;
import std.array;
import std.datetime;
import std.datetime.systime : Clock;
import std.algorithm : each;

import std.typecons;

static struct Cache {
static:
	void startTasks() {
		runWorkerTask(&versionFileTask);
		runWorkerTask(&githubVersionFileTask);
	}

private:
	void versionFileTask() {
		auto mongo = connectToMongo();
		logInfo("VersionFile - Cache task started...");

		while (true) {
			long currentTime = Clock.currTime.toUnixTime!long;
			foreach (VersionFile file; VersionFile.findRange(["lastUpdated" : ["$lte" : (currentTime - 10 * 60)]])) {
				logInfo("Downloading: %s", file.url);
				try {
					Appender!(ubyte[]) data;
					byChunk(file.url).each!(x => data.put(x));
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

	void githubVersionFileTask() {
		auto mongo = connectToMongo();
		logInfo("GitHubVersionFile - Cache task started...");

		while (true) {
			size_t remaining;
			try {
				import std.conv : to;

				logInfo("Grabbing GitHub rate limit:");
				Json rateLimit = get("https://api.github.com/rate_limit").to!string.parseJsonString;
				remaining = rateLimit["rate"]["remaining"].get!size_t;
				logInfo("\tGitHub rate limit is: %d", remaining);
			} catch (CurlException ex) {
				logError("\t Failed to grab GitHub rate limit:\n%s", ex);
				continue;
			} catch (JSONException ex) {
				logError("\t Failed to parse GitHub rate limit:\n%s", ex);
				continue;
			}

			long currentTime = Clock.currTime.toUnixTime!long;
			auto r = GitHubVersionFile.findRange(["lastUpdated" : ["$lte" : (currentTime - 10 * 60)]]);
			for (size_t i; !r.empty && i < remaining; r.popFront, i++) {
				GitHubVersionFile file = r.front;
				logInfo("Downloading: %s", file.url);
				try {
					Appender!(ubyte[]) data;
					byChunk(file.url).each!(x => data.put(x));
					file.data = data.data;
					file.lastUpdated = currentTime;
					file.save();
					logInfo("\tDownloaded a total %d bytes.", file.data.length);
				} catch (CurlException ex) {
					logError("\tDownload failed:\n%s", ex);
				}
				yield();
			}
			sleep(1.minutes);
		}
	}

}

Nullable!BsonObjectID addToCacheFile(string url) {
	{
		auto existingFile = VersionFile.tryFindOne(["url" : url]);
		if (!existingFile.isNull)
			return existingFile.get().bsonID.nullable;
	}

	VersionFile file;
	file.url = url;

	logInfo("Downloading: %s", file.url);
	try {
		Appender!(ubyte[]) data;
		byChunk(file.url).each!(x => data.put(x));
		file.data = data.data;
		file.lastUpdated = Clock.currTime.toUnixTime!long;
		file.save();
		logInfo("\tDownloaded a total %d bytes.", file.data.length);
	} catch (CurlException ex) {
		logError("\tDownload failed:\n%s", ex);
		return Nullable!BsonObjectID.init;
	}

	return file.bsonID.nullable;
}

Nullable!BsonObjectID addToCacheGithub(string githubName) {
	string url = "https://api.github.com/repos/" ~ githubName ~ "/tags";

	{
		auto existingFile = GitHubVersionFile.tryFindOne(["url" : url]);
		if (!existingFile.isNull)
			return existingFile.get().bsonID.nullable;
	}

	GitHubVersionFile file;
	file.url = url;
	file.data = null;
	file.lastUpdated = 0;
	file.save();

	return file.bsonID.nullable;
}
