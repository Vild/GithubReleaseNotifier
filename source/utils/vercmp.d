module utils.vercmp;

struct Version {
	string epoch;
	string version_;
	string release;

	bool opCast(T : bool)() {
		return epoch.length || version_.length || release.length;
	}

	string toString() const {
		import std.format : format;

		return format!"%s%s%s%s%s"(epoch, epoch.length ? ":" : "", version_, release.length ? "-" : "", release);
	}

	int opCmp(const(Version) other) const {
		return opCmp(other);
	}

	int opCmp(ref const(Version) other) const {
		int r = _cmp(epoch, other.epoch);
		if (r)
			return r;
		r = _cmp(version_, other.version_);
		if (r)
			return r;
		// To match the arch way (vercmp) this line is needed.
		// But without it: 2.083.0 > 2.083.0-rc.1 > 2.083.0-beta.2 > 2.083.0-beta.1
		// if (release.length && other.release.length)
		r = _cmp(release, other.release);
		return r;
	}

	private int _cmp(string a, string b) const {
		import std.ascii : isDigit, isAlpha, isAlphaNum;

		if (a == b)
			return 0;

		while (a.length && b.length) {
			while (a.length && !a[0].isAlphaNum && a[0] != '~')
				a = a[1 .. $];
			while (b.length && !b[0].isAlphaNum && b[0] != '~')
				b = b[1 .. $];

			if ((a.length && a[0] == '~') || (b.length && b[0] == '~')) {
				if (a[0] != '~')
					return -1;
				if (b[0] != '~')
					return 1;

				a = a[1 .. $];
				b = b[1 .. $];
				continue;
			}

			if (!a.length || !b.length)
				break;

			bool isDigitPart;
			string aPart, bPart;

			import std.algorithm : countUntil, cmp;

			if (a[0].isDigit) {
				ptrdiff_t aCount = a.countUntil!(x => !x.isDigit);
				ptrdiff_t bCount = b.countUntil!(x => !x.isDigit);

				if (aCount == -1)
					aCount = a.length;
				if (bCount == -1)
					bCount = b.length;

				aPart = a[0 .. aCount];
				bPart = b[0 .. bCount];
				a = a[aCount .. $];
				b = b[bCount .. $];

				isDigitPart = true;
			} else if (a[0].isAlpha) {
				ptrdiff_t aCount = a.countUntil!(x => !x.isAlpha);
				ptrdiff_t bCount = b.countUntil!(x => !x.isAlpha);

				if (aCount == -1)
					aCount = a.length;
				if (bCount == -1)
					bCount = b.length;

				aPart = a[0 .. aCount];
				bPart = b[0 .. bCount];
				a = a[aCount .. $];
				b = b[bCount .. $];

				isDigitPart = false;
			} else
				assert(0);

			if (!bPart.length)
				return isDigitPart ? 1 : -1;

			if (isDigitPart) {
				ptrdiff_t aCount = a.countUntil!(x => x != '0');
				ptrdiff_t bCount = b.countUntil!(x => x != '0');
				if (aCount == -1)
					aCount = a.length;
				if (bCount == -1)
					bCount = b.length;
				aPart = aPart[aCount .. $];
				bPart = bPart[bCount .. $];

				if (aPart.length > bPart.length)
					return 1;
				else if (aPart.length < bPart.length)
					return -1;
			}

			if (auto r = cmp(aPart, bPart))
				return (r < 0) ? -1 : 1;
		}

		if (!a.length && !b.length)
			return 0;

		return ((!a.length && b.length && !b[0].isAlpha) || (a.length && a[0].isAlpha)) ? -1 : 1;
	}
}

void assertVersion(string a, string b, int c) {
	import std.format : format;
	import std.stdio;

	auto verA = getVersion(a);
	auto verB = getVersion(b);

	auto val = verA.opCmp(verB);
	if (val == c)
		return;

	int epochCmp = verA._cmp(verA.epoch, verB.epoch);
	int version_Cmp = verA._cmp(verA.version_, verB.version_);
	int releaseCmp = verA._cmp(verA.release, verB.release);

	// dfmt off
		assert(0, format!`Comparing %s <=> %s
	cmp(epoch, other.epoch): %s
	cmp(version_, other.version_): %s
	cmp(release, other.release): %s
== %d (is should be %d)`(verA, verB, epochCmp, version_Cmp, releaseCmp, val, c));
		// dfmt on
}

// dfmt off
// Testes are mostly from the manpage of `vercmp`
@(`1.0a < 1.0b`) unittest { assertVersion("1.0a", "1.0b", -1); }
@(`1.0b < 1.0beta`) unittest { assertVersion("1.0b", "1.0beta", -1); }
@(`1.0beta < 1.0p`) unittest { assertVersion("1.0beta", "1.0p", -1); }
@(`1.0p < 1.0pre`) unittest { assertVersion("1.0p", "1.0pre", -1); }
@(`1.0pre < 1.0rc`) unittest { assertVersion("1.0pre", "1.0rc", -1); }
@(`1.0rc < 1.0`) unittest { assertVersion("1.0rc", "1.0", -1); }
@(`1.0 < 1.0.a`) unittest { assertVersion("1.0", "1.0.a", -1); }
@(`1.0.a < 1.0.1`) unittest { assertVersion("1.0.a", "1.0.1", -1); }

@(`2:1.0-1 > 1:3.6-1`) unittest { assertVersion("2:1.0-1", "1:3.6-1", 1); }
@(`1.5-1 < 1.5-2`) unittest { assertVersion("1.5-1", "1.5-2", -1); }

@(`1 < 1.0`) unittest { assertVersion("1", "1.0", -1); }
@(`1.0 < 1.1`) unittest { assertVersion("1.0", "1.1", -1); }
@(`1.1 < 1.1.1`) unittest { assertVersion("1.1", "1.1.1", -1); }
@(`1.1.1 < 1.2`) unittest { assertVersion("1.1.1", "1.2", -1); }
@(`1.2 < 2.0`) unittest { assertVersion("1.2", "2.0", -1); }
@(`2.0 < 3.0.0`) unittest { assertVersion("2.0", "3.0.0", -1); }

@(`1 < 2`) unittest { assertVersion("1", "2", -1); }
@(`2 > 1`) unittest { assertVersion("2", "1", 1); }
@(`2.0-1 > 1.7-6`) unittest { assertVersion("2.0-1", "1.7-6", 1); }
@(`4.34 < 1:001`) unittest { assertVersion("4.34", "1:001", -1); }

@(`2.083.0 > 2.083.0-rc.1`) unittest { assertVersion("2.083.0", "2.083.0-rc.1", 1); }
@(`2.083.0-rc.1 > 2.083.0-beta.2`) unittest { assertVersion("2.083.0-rc.1", "2.083.0-beta.2", 1); }
@(`2.083.0-beta.2 > 2.083.0-beta.1`) unittest { assertVersion("2.083.0-beta.2", "2.083.0-beta.1", 1); }


// These will not pass as they break the -rc.1, -beta.x logic
// @(`1.5-1 == 1.5`) unittest { assertVersion("1.5-1", "1.5", 0); }
// @(`2.0 == 2.0-13`) unittest { assertVersion("2.0", "2.0-13", 0); }

// dfmt on

// version format is '[epoch:]version[-release]'
Version getVersion(string ver) {
	import std.regex : matchFirst, ctRegex;

	Version v;

	if (ver.length && ver[0] == 'v')
		ver = ver[1 .. $];

	/***
		^               = Start of line
		(?:[\w]*[\s]+)? = Optionally, find alphaNums{0,∞} that ends with whitespace characters{1,∞}. DISCARD
		(?:([\w.-]+):)? = Optionally, find a epoch (everything before ':'), and discard the ':'
		([\w.]+)        = Find the version
		(?:-([\w.]+))?  = Optionally, find a release (everything after '-'), and discard the '-'
		$               = End of line
	*/
	auto match = ver.matchFirst(ctRegex!`^(?:[\w]*[\s]+)?(?:([\w.-]+):)?([\w.]+)(?:-([\w.]+))?`);
	v.epoch = match[1] ? match[1] : "0";
	v.version_ = match[2];
	v.release = match[3];

	return v;
}
