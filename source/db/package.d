module db;

public import vibe.db.mongo.mongo;
public import mongoschema;
import mongoschema.aliases : name, ignore, unique, binary;
public import vibe.data.bson;
public import vibe.core.log;

import utils.vercmp;

enum mongoDBName = "githubreleasenotifier";
enum DBCollection;

MongoClient connectToMongo() {
	import vibe.core.log;
	import std.traits : getSymbolsByUDA;

	static MongoClient mongo;

	if (!mongo) {
		logInfo("Connecting to MongoDB...");
		mongo = connectMongoDB("127.0.0.1");
	}

	static foreach (dbCollection; getSymbolsByUDA!(mixin(__MODULE__), DBCollection))
		if (!dbCollection.collection.name.length) { // TODO: Fix mongoschema with better multithread/multifiber support
			mongo.getCollection(mongoDBName ~ "." ~ dbCollection.stringof).register!dbCollection;
			logInfo("%s.%s mapped to %s", mongoDBName, dbCollection.stringof, dbCollection.stringof);
		}

	logInfo("MongoDB setup is done");

	return mongo;
}

enum NotificationFrequency {
	instant,
	daily,
	never
}

// The user that is logged in
@DBCollection struct User {
	@unique string username;
	string email; /// Where to send the email to
	string ircNick; /// On freenode
	//TODO: (Google) Firebase Cloud Messaging - Basically a push notification

	@binary() char[] password;

	bool isActivated;
	uint activationCode;

	bool opCast(T : bool)() {
		return bsonID.valid;
	}

	mixin MongoSchema;
}

// TODO: Add support for AUR
enum RemoteSite {
	// git ls-remove <URL> - will give all the tags and sha1 hashes
	git,
	archlinux
}

struct ProcessedVersion {
	Version version_;
	Bson extraData;

	int opCmp(const(ProcessedVersion) other) const {
		return opCmp(other);
	}

	int opCmp(ref const(ProcessedVersion) other) const {
		return version_.opCmp(other.version_);
	}
}

// Represents a file that needs to be pulled to check stuff for projects
@DBCollection struct VersionInfo {
	@unique string url;

	@byName RemoteSite remoteSite;
	size_t lastUpdated; // Timestamp

	BsonObjectID[] projects; // If empty, remove file

	static void addProject(BsonObjectID id, ref Project p) {
		VersionInfo.update(["_id" : id], ["$addToSet" : ["projects" : p.bsonID]]);
	}

	static void removeProject(BsonObjectID id, ref Project p) {
		VersionInfo.update(["_id" : id], ["$pull" : ["projects" : p.bsonID]]);
		// TODO: Some remove file if not in used. or cron job?

		// VersionInfo.collection.remove(["_id" : id, ""])
	}

	ProcessedVersion[] versions;

	mixin MongoSchema;
}

// A project instance for a user
@DBCollection struct Project {
	string name; // dlang/dmd

	BsonObjectID owner;

	string lastNotifiedVersion;

	// TODO: Change this to just git

	string gitName;
	BsonObjectID gitInfo;
	//TODO: Return more than one version (incase two tags points to the same commit)
	@property ProcessedVersion gitVersion() {
		import std.algorithm : filter;
		Nullable!VersionInfo v = VersionInfo.tryFindById(gitInfo);

		if (v.isNull)
			return ProcessedVersion.init;

		import std.algorithm : sort;
		auto vVersions = v.versions.sort!"a > b";

		if (ignorePreRelease) {
			auto versions = vVersions.filter!"!a.version_.release.length";

			return !versions.empty ? versions.front : ProcessedVersion.init;
		} else
			return vVersions.length ? vVersions[0] : ProcessedVersion.init;
	}

	string archlinuxName; // community/x86_64/dmd
	BsonObjectID archlinuxInfo;
	@property ProcessedVersion archlinuxVersion() {
		Nullable!VersionInfo v = VersionInfo.tryFindById(archlinuxInfo);
		if (v.isNull)
			return ProcessedVersion.init;

		return v.versions.length ? v.versions[0] : ProcessedVersion.init;
	}

	bool ignorePreRelease = true;

	bool notifyViaEmail;
	bool notifyViaIRC;

	mixin MongoSchema;

	void triggerUpdate() {
		import actions.email;
		import backends.git;

		auto gitV = gitVersion;
		if (getVersion(lastNotifiedVersion) == gitV.version_) // TODO: <=
			return;

		User user = User.findById(owner);

		if (notifyViaEmail)
			sendNewReleaseEmail(user.username, user.email, name, gitV);

		lastNotifiedVersion = gitV.version_.toString;
		save();
	}
}
