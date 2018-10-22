module db;

public import vibe.db.mongo.mongo;
public import mongoschema;
import mongoschema.aliases : name, ignore, unique, binary;
public import vibe.data.bson;

import utils.vercmp;

enum mongoDBName = "githubreleasenotifier";

MongoClient connectToMongo() {
	MongoClient mongo = connectMongoDB("127.0.0.1");
	mongo.getCollection(mongoDBName ~ ".users").register!User;
	mongo.getCollection(mongoDBName ~ ".versionFiles").register!VersionFile;
	mongo.getCollection(mongoDBName ~ ".githubVersionFiles").register!GitHubVersionFile;
	mongo.getCollection(mongoDBName ~ ".projects").register!Project;
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

		return getGitHubVersions(this)[0].version_;
	}

	///// If this project have a ArchLinux package, fill these out!
	BsonObjectID archlinuxFile;
	string archlinuxName; // community/x86_64/dmd
	@property Version archlinuxVersion() {
		import backends.archlinux;

		return getArchlinuxVersion(this);
	}

	bool notifyViaEmail;
	bool notifyViaIRC;

	mixin MongoSchema;
}
