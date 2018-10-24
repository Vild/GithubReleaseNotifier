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

	mixin MongoSchema;
}

// Represents a file that needs to be pulled to check stuff for projects
struct VersionFile {
	@unique string url;
	@binary() ubyte[] data;
	size_t lastUpdated;

	mixin MongoSchema;
}

struct GitHubVersionFile {
	@unique string url;
	@binary() ubyte[] data;
	size_t lastUpdated;

	mixin MongoSchema;
}

// A project instance for a user
struct Project {
	@unique string name; // dlang/dmd

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
