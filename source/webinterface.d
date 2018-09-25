module webinterface;

import vibe.http.server;
import vibe.core.core;
import vibe.web.web;
import vibe.web.auth;
import db;
import std.typecons : Nullable;
import deimos.sodium;
import vibe.core.net;
import std.string;
import std.uni;
import email;

// https://github.com/vibe-d/vibe.d/blob/03b85894ff8e88f3f92001c0750f809aa3ccb1f8/examples/web-auth/source/app.d

struct AuthInfo {
@safe:
	string username;
	BsonObjectID userID;

	/*bool isAdmin() {
		return this.admin;
	}

	bool isPremiumUser() {
		return this.premium;
	}*/

	bool opCast(T : bool)() {
		return userID.valid;
	}
}

@requiresAuth class WebInterface {
private:
	MongoClient _mongo;

	enum _pwOpsLimit = crypto_pwhash_OPSLIMIT_INTERACTIVE;
	enum _pwMemLimit = crypto_pwhash_MEMLIMIT_INTERACTIVE;
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

		@errorDisplay!getLogin void postLogin(ValidUsername username, ValidPassword password, scope HTTPServerRequest req,
				scope HTTPServerResponse res) {
			import vibe.core.net : enforce;

			// A 'generic' error message is uses so an attacker don't know if the username or if the password was wrong!
			string loginError = "Invalid username or password!";

			Nullable!User user = User.tryFindOne(["username" : username.toLower]);
			enforce(!user.isNull, loginError);

			immutable(char)[] pw = password.toStringz[0 .. password.length];
			enforce(crypto_pwhash_str_verify(user.password[0 .. crypto_pwhash_STRBYTES], pw.ptr, pw.length) == 0, loginError);

			if (crypto_pwhash_str_needs_rehash(user.password[0 .. crypto_pwhash_STRBYTES], _pwOpsLimit, _pwMemLimit) != 0)
				if (crypto_pwhash_str(user.password[0 .. crypto_pwhash_STRBYTES], pw.ptr, pw.length, _pwOpsLimit, _pwMemLimit) == 0)
					user.save();

			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			if (!user.isActivated) {
				redirect("/activate?from=" ~ from ~ "&username=" ~ username);
				return;
			}

			AuthInfo auth;
			auth.username = user.username;
			auth.userID = user.bsonID;

			req.session = res.startSession;
			req.session.set("auth", auth);
			redirect(from);
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
			import std.random;

			enforce(password == password2, "Passwords does not match");

			User user;
			user.username = username.toLower;
			user.email = email.toString;
			user.ircNick = irc;
			user.activationCode = randombytes_random();

			immutable(char)[] pw = password.toStringz[0 .. password.length];
			user.password.length = crypto_pwhash_STRBYTES;
			enforce(crypto_pwhash_str(user.password[0 .. crypto_pwhash_STRBYTES], pw.ptr, pw.length, _pwOpsLimit,
					_pwMemLimit) == 0, "Password hashing failed!");

			user.save();

			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			runWorkerTask(&sendActivationEmail, user.username, user.email, user.activationCode);

			redirect("/activate?from=" ~ from ~ "&username=" ~ username);
		}

		void getActivate(scope HTTPServerRequest req, string _error = null) {
			string error = _error;
			Nullable!AuthInfo auth;
			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;
			string username;
			if (auto _ = "username" in req.form)
				username = *_;
			else if (auto _ = "username" in req.query)
				username = *_;

			enforce(username, "Username is missing! Please use the link in the email!");

			string code = "";
			if (auto _ = "code" in req.query)
				code = *_;

			if ("resend" in req.query) {
				Nullable!User user = User.tryFindOne(["username" : username.toLower]);
				enforce(!user.isNull, "Cannot find the user!");
				enforce(!user.isActivated, "The account is already activated!");

				user.activationCode = randombytes_random();
				user.save();

				runWorkerTask(&sendActivationEmail, user.username, user.email, user.activationCode);
			}

			if (req.session && req.session.isKeySet("auth"))
				redirect(from);
			else
				render!("activate.dt", auth, from, username, code, error);
		}

		@errorDisplay!getActivate void postActivate(ValidUsername username, string code, scope HTTPServerRequest req,
				scope HTTPServerResponse res) {
			import std.format : format;

			Nullable!User user = User.tryFindOne(["username" : username.toLower]);
			enforce(!user.isNull, "Cannot find the user!");
			enforce(!user.isActivated, "The account is already activated!");

			enforce(code.toUpper == format!"%08X"(user.activationCode), "Activation code is wrong!");

			user.isActivated = true;

			user.save();

			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			redirect("/login?from=" ~ from);
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
