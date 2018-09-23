module webinterface;

import vibe.http.server;
import vibe.web.web;
import vibe.web.auth;
import db;
import std.typecons : Nullable;
import deimos.sodium;
import vibe.core.net : enforce;

// https://github.com/vibe-d/vibe.d/blob/03b85894ff8e88f3f92001c0750f809aa3ccb1f8/examples/web-auth/source/app.d

struct AuthInfo {
@safe:
	string userName;
	BsonObjectID user;
	bool admin;
	bool premium;

	bool isAdmin() {
		return this.admin;
	}

	bool isPremiumUser() {
		return this.premium;
	}

	bool opCast(T : bool)() {
		return !!userName;
	}
}

@requiresAuth class WebInterface {
	private MongoClient _mongo;
public:
	this() {
		sodium_init();
		_mongo = connectToMongo();

		if (!VersionFile.countAll()) {
			// dfmt off
			VersionFile[] files = [
				VersionFile("https://www.archlinux.org/packages/community/x86_64/dmd/json/", null, 0)
			];
			// dfmt on
			foreach (ref file; files)
				file.save();
		}
	}

	@noRoute AuthInfo authenticate(scope HTTPServerRequest req, scope HTTPServerResponse res) @safe {
		if (!req.session || !req.session.isKeySet("auth")) {
			//throw new HTTPStatusException(HTTPStatus.forbidden, "Not authorized to perform this action!");
			res.redirect("/login?from=" ~ req.requestURI);
			return AuthInfo.init;
		}
		return req.session.get!AuthInfo("auth");
	}

	@noAuth {
		void index(scope HTTPServerRequest req) {
			Nullable!AuthInfo auth;
			if (req.session && req.session.isKeySet("auth"))
				auth = req.session.get!AuthInfo("auth");
			render!("index.dt", auth);
		}

		void getLogin(scope HTTPServerRequest req, string _error = null) {
			string error = _error;
			Nullable!AuthInfo auth;
			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			if (req.session && req.session.isKeySet("auth"))
				redirect(from);
			else
				render!("login.dt", auth, from, error);
		}

		@errorDisplay!getLogin void postLogin(ValidUsername username, string password, scope HTTPServerRequest req, scope HTTPServerResponse res) {
			import vibe.core.net : enforce;

			enforce(password == "secret", "Invalid password.");

			AuthInfo s = {userName:
			username};
			req.session = res.startSession;
			req.session.set("auth", s);
			if (auto from = "from" in req.query)
				redirect(*from);
			else
				redirect("/");
		}

		void getRegister(scope HTTPServerRequest req, string _error = null) {
			string error = _error;
			Nullable!AuthInfo auth;
			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			if (req.session && req.session.isKeySet("auth"))
				redirect(from);
			else
				render!("register.dt", auth, from, error);
		}

		@errorDisplay!getRegister void postRegister(ValidUsername username, ValidEmail email, ValidPassword password,
				ValidPassword password2, string irc, scope HTTPServerRequest req, scope HTTPServerResponse res) {
			enforce(password == password2, "Passwords does not match");

			User user;
			user.username = username.toString;
			user.email = email.toString;
			user.ircNick = irc;

			string pw = password.toString;
			char[crypto_pwhash_STRBYTES] hash;
			enforce(crypto_pwhash_str(hash, pw.ptr, pw.length, crypto_pwhash_OPSLIMIT_INTERACTIVE,
					crypto_pwhash_MEMLIMIT_INTERACTIVE) == 0, "Password hashing failed!");
			user.password = hash;

			user.save();

			if (auto from = "from" in req.query)
				redirect(*from);
			else
				redirect("/");
		}
	}

	@anyAuth {
		void getDashboard(AuthInfo auth) {
			// dfmt off
			Project[] projects = [
				Project.loadCache("dlang/dmd", "dlang/dmd", "community/x86_64/dmd"),
				Project.loadCache("ldc-developers/ldc", "ldc-developers/ldc", "community/x86_64/ldc"),
				Project.loadCache("dlang-community/dfmt", "dlang-community/dfmt", "community/x86_64/dfmt"),
				Project.loadCache("dlang-community/D-Scanner", "dlang-community/D-Scanner", "community/x86_64/dscanner"),
				Project.loadCache("dlang-community/DCD", "dlang-community/DCD", "community/x86_64/dcd"),
				Project.loadCache("Pure-D/serve-d", "Pure-D/serve-d", null),
			];
			// dfmt on
			render!("dashboard.dt", auth, projects);
		}

		void postLogout() {
			terminateSession();
			redirect("/");
		}

		void getLogout() {
			terminateSession();
			redirect("/");
		}

		/*

		// GET /settings
		// authUser is automatically injected based on the authenticate() result
		void getSettings(AuthInfo auth, string _error = null)
		{
			auto error = _error;
			render!("settings.dt", error, auth);
		}

		// POST /settings
		// @errorDisplay will render errors using the getSettings method.
		// authUser gets injected with the associated authenticate()
		@errorDisplay!getSettings
		void postSettings(bool premium, bool admin, ValidUsername user_name, AuthInfo authUser, scope HTTPServerRequest req)
		{
			AuthInfo s = authUser;
			s.userName = user_name;
			s.premium = premium;
			s.admin = admin;
			req.session.set("auth", s);
			redirect("/");
}
		*/
	}
}
