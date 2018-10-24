module db;

public import vibe.db.mongo.mongo;
public import mongoschema;
import mongoschema.aliases : name, ignore, unique, binary;
public import vibe.data.bson;

import utils.vercmp;

enum mongoDBName = "githubreleasenotifier";

MongoClient connectToMongo() {
	import vibe.core.log;

	static MongoClient mongo;

	if (!mongo) {
		logInfo("Connecting to MongoDB...");
		mongo = connectMongoDB("127.0.0.1");
	}

	// TODO: Fix mongoschema with better multithread/multifiber support
	if (!User.collection.name.length)
		mongo.getCollection(mongoDBName ~ ".users").register!User;
	if (!VersionFile.collection.name.length)
		mongo.getCollection(mongoDBName ~ ".versionFiles").register!VersionFile;
	if (!GitHubVersionFile.collection.name.length)
		mongo.getCollection(mongoDBName ~ ".githubVersionFiles").register!GitHubVersionFile;
	if (!Project.collection.name.length)
		mongo.getCollection(mongoDBName ~ ".projects").register!Project;
	logInfo("MongoDB setup is done");

	return mongo;
}

enum NotificationFrequency {
	instant,
	daily,
	never
}

// The user that is logged in
struct User {
	@unique string username;
	string email; /// Where to send the email to
	string ircNick; /// On freenode
	//TODO: (Google) Firebase Cloud Messaging - Basically a push notification

	@binary() char[] password;

	bool isActivated;
	uint activationCode;

	BsonObjectID[] projects;

	bool opCast(T : bool)() {
		return bsonID.valid;
	}

	//TODO: move?
	void checkUpdate() {
		import actions.email;
		import backends.github;

		BsonObjectID[] updatedProjects;
		foreach (BsonObjectID pID; projects) {
			Nullable!Project pNull = Project.tryFindById(pID);
			if (pNull.isNull)
				continue;

			Project p = pNull.get();
			updatedProjects ~= pID;

			auto versions = getGitHubVersions(p, p.ignorePreRelease);
			if (!versions.length)
				continue;

			if (getVersion(p.lastNotifiedVersion) == versions[0].version_) // TODO: <=
				continue;

			if (p.notifyViaEmail)
				sendNewReleaseEmail(username, email, p.name, versions[0]);

			p.lastNotifiedVersion = versions[0].version_.toString;
			p.save();
		}

		if (projects.length != updatedProjects.length) {
			updatedProjects = projects;
			save();
		}
	}

	mixin MongoSchema;
}

// TODO: MOVE!
void userCheckUpdates() {
	import vibe.core.log;
	import vibe.core.core;
	import std.datetime;
	connectToMongo();
	logInfo("User - Update checker task started...");

	while (true) {
		foreach (User u; User.findAll)
			u.checkUpdate();

		sleep(10.seconds);
	}
}

// Represents a file that needs to be pulled to check stuff for projects
struct VersionFile {
	@unique string url;
	@binary() ubyte[] data;
	size_t lastUpdated;

	// TODO: BsonObjectID[] users;
	// or BsonObjectID[] projects;

	mixin MongoSchema;
}

struct GitHubVersionFile {
	@unique string url;
	@binary() ubyte[] data;
	size_t lastUpdated;

	// TODO: BsonObjectID[] users;
	// or BsonObjectID[] projects;

	mixin MongoSchema;
}

// A project instance for a user
struct Project {
	string name; // dlang/dmd

	// TODO: BsonObjectID[] owners;
	// or BsonObjectID owner;

	string lastNotifiedVersion;

	// TODO: Change this to just git
	// git ls-remove <URL> - will give all the tags and sha1 hashes
	BsonObjectID githubFile;
	string githubName;
	@property Version githubVersion() {
		import backends.github;

		auto versions = getGitHubVersions(this, ignorePreRelease);
		return versions.length ? versions[0].version_ : Version.init;
	}

	///// If this project have a ArchLinux package, fill these out!
	BsonObjectID archlinuxFile;
	string archlinuxName; // community/x86_64/dmd
	@property Version archlinuxVersion() {
		import backends.archlinux;

		return getArchlinuxVersion(this);
	}

	bool ignorePreRelease = true;

	bool notifyViaEmail;
	bool notifyViaIRC;

	mixin MongoSchema;
}
