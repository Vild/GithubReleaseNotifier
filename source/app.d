import vibe.vibe;
import mongoschema;
import vibe.db.mongo.sessionstore;

import db;
import webinterface;
import db.cache;

import std.process : spawnShell, tryWait, kill, Pid;

shared static this() {
	import etc.linux.memoryerror;

	static if (is(typeof(registerMemoryErrorHandler)))
		registerMemoryErrorHandler();
}

debug Pid chromium;
void main() {
	connectToMongo();

	auto settings = new HTTPServerSettings;
	settings.port = 4000;
	settings.bindAddresses = ["0.0.0.0"];
	settings.sessionStore = new MongoSessionStore("mongodb://127.0.0.1/" ~ mongoDBName, "sessions");
	settings.errorPageHandler = (scope HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error) {
		logError("==HTTP Error %d==
An error has occured. We are really sorry about that!
Error description:
\t%s
Exceptions:
\t%s\n", error.code, error.debugMessage, error.exception);
		logError("==HTTP Error %d==
An error has occured. We are really sorry about that!
Error description:
\t%s
Exceptions:
\t%s\n", error.code, error.debugMessage, error.exception);
		res.render!("error.dt", req, error);
	};

	auto router = new URLRouter;
	router.registerWebInterface(new WebInterface);
	router.get("/quit", (scope HTTPServerRequest req, HTTPServerResponse res) {
		debug kill(chromium);
		exitEventLoop(true);
		res.writeVoidBody;
	});
	router.get("*", serveStaticFiles("./public/"));
	//router.registerRestInterface(new MyAPIImplementation, "/api/");

	listenHTTP(settings, router);

	Cache.startTasks();
	runWorkerTask(&userCheckUpdates);

	debug {
		scope (exit)
			if (!tryWait(chromium).terminated)
				kill(chromium);
		runTask({
			import std.conv : text;

			chromium = spawnShell(
				"chromium --user-data-dir=/tmp/webdev-chromium-instance --app=http://" ~ settings.bindAddresses[0] ~ ":" ~ settings.port.text ~ "/");
			while (!tryWait(chromium).terminated)
				sleep(1.seconds);

			exitEventLoop(true);
		});
	}

	runApplication();
}
