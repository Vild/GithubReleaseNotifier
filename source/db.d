module db;

public import vibe.db.mongo.mongo;
public import mongoschema;
import mongoschema.aliases : name, ignore, unique, binary;
public import vibe.data.bson;

import vercmp;

MongoClient connectToMongo() {
	MongoClient mongo = connectMongoDB("127.0.0.1");
	mongo.getCollection("githubreleasenotifier.users").register!User;
	mongo.getCollection("githubreleasenotifier.versionFiles").register!VersionFile;
	mongo.getCollection("githubreleasenotifier.projects").register!Project;
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

	BsonObjectID[] projects;

	mixin MongoSchema;
}

// Represents a file that needs to be pulled to check stuff for projects
struct VersionFile {
	@unique string url;
	@binary() ubyte[] data;
	size_t lastUpdated;

	mixin MongoSchema;
}

// A project instance for a user
struct Project {
	string name; // dlang/dmd

	BsonObjectID githubFile;
	string githubName;
	Version githubVersion;

	///// If this project have a ArchLinux package, fill these out!
	BsonObjectID archlinuxFile;
	string archlinuxName; // community/x86_64/dmd
	Version archlinuxVersion;

	// bool notifyViaEmail;
	// bool notifyViaIrc;

	debug static Project loadCache(string name, string githubName, string archlinuxName) {
		import github;
		import archlinux;

		Project p;
		p.name = name;

		p.githubName = githubName;
		//p.githubURL = "https://github.com/" ~ githubName;
		p.githubVersion = getGithubVersions(p)[0];

		p.archlinuxName = archlinuxName;
		//p.archlinuxNameURL = "https://www.archlinux.org/packages/" ~ archlinuxName;
		p.archlinuxVersion = getArchlinuxVersion(p);

		return p;
	}

	mixin MongoSchema;
}
