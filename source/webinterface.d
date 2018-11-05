module webinterface;

import vibe.http.server;
import vibe.core.core;
import vibe.core.log;
import vibe.web.web;
import vibe.web.auth;
import db;
import std.typecons : Nullable;
import deimos.sodium;
import vibe.core.net;
import std.string;
import std.uni;
import std.exception;
import actions.email;

struct AuthInfo {
@safe:
	string username;
	BsonObjectID userID;

	@property User user() @trusted {
		return User.findById(userID);
	}

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

struct WebError {
	Exception ex;
	string field;

	bool opCast(T : bool)() {
		return !!ex;
	}

	void toString(scope void delegate(const(char)[]) @safe sink) const {
		import std.format : formattedWrite;

		if (!ex)
			return;

		sink.formattedWrite("%s", ex.msg);

		debug {
			sink.formattedWrite("ex: ");
			ex.toString(sink);
			sink.formattedWrite("field: %s", field);
		}
	}
}

@requiresAuth class WebInterface {
private:
	enum _pwOpsLimit = crypto_pwhash_OPSLIMIT_INTERACTIVE;
	enum _pwMemLimit = crypto_pwhash_MEMLIMIT_INTERACTIVE;
public:
	this() {
		sodium_init();
		connectToMongo();
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

		void getLogin(scope HTTPServerRequest req, WebError _error = WebError()) {
			WebError error = _error;
			Nullable!AuthInfo auth;
			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			string username;
			if (auto _ = "username" in req.form)
				username = *_;

			if (req.session && req.session.isKeySet("auth"))
				redirect(from);
			else
				render!("login.dt", auth, from, username, error);
		}

		@errorDisplay!getLogin void postLogin(ValidUsername username, ValidPassword password, scope HTTPServerRequest req,
				scope HTTPServerResponse res) {
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

		void getRegister(scope HTTPServerRequest req, WebError _error = WebError()) {
			WebError error = _error;
			Nullable!AuthInfo auth;
			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			string username;
			if (auto _ = "username" in req.form)
				username = *_;

			string email;
			if (auto _ = "email" in req.form)
				email = *_;

			string irc;
			if (auto _ = "irc" in req.form)
				irc = *_;

			if (req.session && req.session.isKeySet("auth"))
				redirect(from);
			else
				render!("register.dt", auth, from, username, email, irc, error);
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

		@errorDisplay!getActivate void getActivate(scope HTTPServerRequest req, WebError _error = WebError()) {
			WebError error = _error;
			Nullable!AuthInfo auth;
			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;
			string username;
			if (auto _ = "username" in req.form)
				username = *_;
			else if (auto _ = "username" in req.query)
				username = *_;

			if (!_error) {
				enforce(username, "Username is missing! Please use the link in the email!");

				if ("resend" in req.query) {
					Nullable!User user = User.tryFindOne(["username" : username.toLower]);
					enforce(!user.isNull, "Cannot find the user!");
					enforce(!user.isActivated, "The account is already activated!");

					user.activationCode = randombytes_random();
					user.save();

					runWorkerTask(&sendActivationEmail, user.username, user.email, user.activationCode);
				} else if (auto code = "code" in req.query) {
					_activateAccount(username, *code);
					redirect(from);
				}
			}

			if (req.session && req.session.isKeySet("auth"))
				redirect(from);
			else
				render!("activate.dt", auth, from, username, error);
		}

		@errorDisplay!getActivate void postActivate(ValidUsername username, string code, scope HTTPServerRequest req,
				scope HTTPServerResponse res) {
			import std.format : format;

			_activateAccount(username, code);

			string from = "/";
			if (auto _ = "from" in req.query)
				from = *_;

			redirect("/login?from=" ~ from);
		}
	}

	@anyAuth {
		void getDashboard(AuthInfo auth, scope HTTPServerRequest req) {
			import std.array : array;

			auto query(Q, S)(Q q, S s) {
				struct Query(Q, S) {
					Q query;
					S orderby;
				}

				return Query!(Q, S)(q, s);
			}

			auto projects = Project.findRange(query(["owner" : auth.userID], ["name" : 1])).array;
			render!("dashboard.dt", auth, projects);
		}

		@path("/project/:projectName")
		@errorDisplay!getEditProject void postEditProject(AuthInfo auth, string _projectName, string name, string gitName,
				bool ignorePreRelease, bool notifyViaEmail, bool notifyViaIRC, string archlinuxName, scope HTTPServerRequest req) {
			import std.algorithm : count;
			import std.format : format;

			string projectName = _projectName;

			auto projects = Project.findRange(["owner" : auth.userID]).find!"a.name == b"(projectName);
			enforce(!projects.empty, "Project is missing!");
			Project p = projects.front;

			//TODO: enforce(gitName.count("/") == 1, format!"Git path is in the wrong format! count: %d"(gitName.count("/")));
			enforce(!archlinuxName || archlinuxName.count("/") == 2,
					format!"The Archlinux path is in the wrong format! %s count: %d"(!archlinuxName, archlinuxName.count("/")));

			BsonObjectID oldGitInfo = p.gitInfo;
			BsonObjectID oldArchlinuxInfo = p.archlinuxInfo;

			p.name = name;
			p.gitName = gitName;
			if (p.gitName.length) {
				import db.cache;

				Nullable!BsonObjectID info = constructVersionInfo(p.gitName, RemoteSite.git);
				enforce(!info.isNull, "Git path is wrong! Does the git repo exist?");
				p.gitInfo = info.get();
			} else
				p.gitInfo = BsonObjectID.init;

			p.archlinuxName = archlinuxName;
			if (p.archlinuxName.length) {
				import db.cache;

				Nullable!BsonObjectID info = constructVersionInfo("https://www.archlinux.org/packages/" ~ archlinuxName ~ "/json/",
						RemoteSite.archlinux);
				enforce(!info.isNull, "Archlinux path is wrong! Does the package exist?");
				p.archlinuxInfo = info.get();
			} else
				p.archlinuxInfo = BsonObjectID.init;

			p.ignorePreRelease = ignorePreRelease;

			p.notifyViaEmail = notifyViaEmail;
			p.notifyViaIRC = notifyViaIRC;

			p.save();

			if (oldGitInfo != p.gitInfo) {
				if (oldGitInfo.valid)
					VersionInfo.removeProject(oldGitInfo, p);
				if (p.gitInfo.valid)
					VersionInfo.addProject(p.gitInfo, p);
			}

			if (oldArchlinuxInfo != p.archlinuxInfo) {
				if (oldArchlinuxInfo.valid)
					VersionInfo.removeProject(oldArchlinuxInfo, p);
				if (p.archlinuxInfo.valid)
					VersionInfo.addProject(p.archlinuxInfo, p);
			}

			redirect("/dashboard");
		}

		@path("/project/:projectName")
		void getEditProject(AuthInfo auth, string _projectName, scope HTTPServerRequest req, WebError _error = WebError()) {
			import std.algorithm : find;

			WebError error = _error;
			string projectName = _projectName;

			auto projects = Project.findRange(["owner" : auth.userID]).find!"a.name == b"(projectName);
			Nullable!Project project;
			if (!projects.empty)
				project = projects.front;
			render!("edit_project.dt", auth, projectName, project, error);
		}

		@path("/project/:projectName/remove")
		@errorDisplay!getEditProject void getRemoveProject(AuthInfo auth, string _projectName, scope HTTPServerRequest requestURL) {
			import std.algorithm : find, countUntil, remove;

			string projectName = _projectName;

			auto projects = Project.findRange(["owner" : auth.userID]).find!"a.name == b"(projectName);
			if (projects.empty)
				redirect("/dashboard");

			Project p = projects.front;
			p.remove();

			redirect("/dashboard");
		}

		void getAddProject(AuthInfo auth, scope HTTPServerRequest req, WebError _error = WebError()) {
			WebError error = _error;
			string name;
			if (auto _ = "name" in req.form)
				name = *_;

			string gitName;
			if (auto _ = "gitName" in req.form)
				gitName = *_;

			bool ignorePreRelease = !("name" in req.form) || !!("ignorePreRelease" in req.form);

			bool notifyViaEmail = !!("notifyViaEmail" in req.form);
			bool notifyViaIRC = !!("notifyViaIRC" in req.form);

			string archlinuxName;
			if (auto _ = "archlinuxName" in req.form)
				archlinuxName = *_;

			render!("add_project.dt", auth, name, gitName, ignorePreRelease, notifyViaEmail, notifyViaIRC, archlinuxName, error);
		}

		@errorDisplay!getAddProject void postAddProject(AuthInfo auth, string name, string gitName, bool ignorePreRelease,
				bool notifyViaEmail, bool notifyViaIRC, string archlinuxName, scope HTTPServerRequest req) {
			import std.algorithm : count;
			import std.format : format;

			//TODO: enforce(gitName.count("/") == 1, );
			enforce(!archlinuxName || archlinuxName.count("/") == 2,
					format!"The Archlinux path is in the wrong format! %s count: %d"(!archlinuxName, archlinuxName.count("/")));

			Project p;
			p.name = name;
			p.owner = auth.userID;

			p.gitName = gitName;
			if (p.gitName.length) {
				import db.cache;

				Nullable!BsonObjectID info = constructVersionInfo(p.gitName, RemoteSite.git);
				enforce(!info.isNull, "Git path is wrong! Does the git repo exist?");
				p.gitInfo = info.get();
			} else
				p.gitInfo = BsonObjectID.init;

			p.archlinuxName = archlinuxName;
			if (p.archlinuxName.length) {
				import db.cache;

				Nullable!BsonObjectID info = constructVersionInfo("https://www.archlinux.org/packages/" ~ archlinuxName ~ "/json/",
						RemoteSite.archlinux);
				enforce(!info.isNull, "Archlinux path is wrong! Does the package exist?");
				p.archlinuxInfo = info.get();
			} else
				p.archlinuxInfo = BsonObjectID.init;

			p.ignorePreRelease = ignorePreRelease;

			p.notifyViaEmail = notifyViaEmail;
			p.notifyViaIRC = notifyViaIRC;

			p.save();

			if (p.gitInfo.valid)
				VersionInfo.addProject(p.gitInfo, p);
			if (p.archlinuxInfo.valid)
				VersionInfo.addProject(p.archlinuxInfo, p);

			redirect("/dashboard");
		}

		void postLogout() {
			terminateSession();
			redirect("/");
		}

		void getLogout() {
			terminateSession();
			redirect("/");
		}
	}

private:
	void _activateAccount(string username, string code) {
		Nullable!User user = User.tryFindOne(["username" : username.toLower]);
		enforce(!user.isNull, "Cannot find the user!");
		enforce(!user.isActivated, "The account is already activated!");

		enforce(code.toUpper == format!"%08X"(user.activationCode), "Activation code is wrong!");

		user.isActivated = true;

		user.save();
	}
}
