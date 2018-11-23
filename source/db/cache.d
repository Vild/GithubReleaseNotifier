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
	}

private:
	void versionFileTask() {
		connectToMongo();
		logInfo("VersionInfo - Cache task started...");

		while (true) {
			long currentTime = Clock.currTime.toUnixTime!long;
			foreach (VersionInfo file; VersionInfo.findRange(["lastUpdated" : ["$lte" : (currentTime - 30 * 60)]])) {
				import std.utf : validate;

				validate(file.url);
				logInfo("[%s] Checking: '%s'", file.remoteSite, file.url);
				final switch (file.remoteSite) {
				case RemoteSite.git:
					import backends.git;

					file.versions = getGitVersions(file);
					break;
				case RemoteSite.archlinux:
					import backends.archlinux;

					file.versions = getArchlinuxVersion(file);
					break;
				}

				if (!file.versions.length) {
					logWarn("\tFailed to get data!");
					continue;
				}

				file.lastUpdated = currentTime;
				file.save();

				foreach (BsonObjectID pId; file.projects) {
					Nullable!Project p = Project.tryFindById(pId);
					if (!p.isNull)
						p.get.triggerUpdate();
					else
						logWarn("Project '%s' is missing. Probably forgot to remove it from the VersionFile (%s)", pId, file.bsonID);
				}
				yield();
			}

			sleep(30.seconds);
		}
	}
}

Nullable!BsonObjectID constructVersionInfo(string url, RemoteSite remoteSite) {
	{
		auto existingFile = VersionInfo.tryFindOne(["url" : url]);
		if (!existingFile.isNull)
			return existingFile.get().bsonID.nullable;
	}

	VersionInfo file;
	file.url = url;
	file.remoteSite = remoteSite;

	logInfo("[%s] Checking: %s", file.remoteSite, file.url);
	final switch (file.remoteSite) {
	case RemoteSite.git:
		import backends.git;

		file.versions = getGitVersions(file);
		break;
	case RemoteSite.archlinux:
		import backends.archlinux;

		file.versions = getArchlinuxVersion(file);
		break;
	}

	if (!file.versions.length)
		return typeof(return).init;

	long currentTime = Clock.currTime.toUnixTime!long;
	file.lastUpdated = currentTime;
	file.save();

	return file.bsonID.nullable;
}
