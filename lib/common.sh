[ "$COMMON_SH" ] && return
COMMON_SH=1

################################################################################

# Fatal error if an untested command failed.
set -e

# Fatal error if usage of an undefined variable.
set -u

# Adds “tools/” to the $PATH.
PATH=$SCRIPT_DIR/../tools${PATH:+:$PATH}
export PATH

# Imports PSL.
. psl.sh

################################################################################

#
#
# Note: the validator may print explanations.
#
# prompt @RESULT MESSAGE [VALIDATOR [DEFAULT]]
prompt()
{
	$psl_local _prompt_res _prompt_msg

	_prompt_msg="$2"

	[ $# -ge 4 ] && _prompt_msg="$_prompt_msg [$4]"

	while :
	do
		IFS= read -p "$_prompt_msg " -r _prompt_res || return

		# The input is empty and there is a default value.
		if ! [ "$_prompt_res" ] && [ $# -ge 4 ]
		then
			_prompt_res=$4
			break;
		fi

		# There is no defined validator or the input is valid.
		if ! [ "$3" ] || "$3" "$_prompt_res"
		then
			break
		fi
	done

	eval $1'=$_prompt_res'
}

################################################################################

# fmt_pkg_name NAME VERSION ARCHITECTURE
fmt_pkg_name()
{
	psl_print "${1}_${2}_${3}"
}

# Splits a full package name to its components.
#
# A full package name has the following format: NAME_VERSION[_ARCHITURE].
#
# If there is no “_ARCHITECTURE” part, the architecture is set to “all”.
#
# split_pkg_name PACKAGE @NAME @VERSION @ARCHITECTURE
split_pkg_name()
{
	$psl_local psl

	IFS=_ read -r "$2" "$3" psl <<EOF
$1
EOF

	# Sets a default value for the architecture.
	: ${psl:=all}

	# Assigns this value to the variable named "$4".
	psl_set_value "$4"
}

# Builds a package from a recipe.
#
# build RECIPE
build()
(
	$psl_local \
		psl \
		recipe package \
		name vers arch \
		tmpdir

	[ -f "$1/control" ] \
		|| psl_fatal "this is not a valid recipe: $recipe"

	psl=$1; psl_protect; recipe=$psl
	psl_basename; package=$psl
	split_pkg_name "$package" name vers arch

	# Creation of the base directory.
	tmpdir=$(mktemp --directory)
	cd "$tmpdir"
	mkdir --parents debian

	# Creation of the compat file.
	psl_println 9 > debian/compat

	# Creation of the control file.
	{
		printf '%s\n' \
			"Package:      $name" \
			"Version:      $vers" \
			"Architecture: $arch"

		cat "$recipe/control" | perl -ne 's/^#.*//; print unless /^$/'
	} > debian/control

	# Copy or creation of the changelog.
	if [ -f "$recipe/changelog" ]
	then
		cp --target-directory=debian "$recipe/changelog"
	else
		DATE=$(date --rfc-2822) \
			PACKAGE=$name \
			VERSION=$vers \
			USERNAME=Nobody \
			EMAIL=nobody@nowhere.tld \
			configure < "$SCRIPT_DIR"/.internal/resources/changelog.in > debian/changelog
	fi

	fakeroot -s fakeroot.db true
	#dh_testdir
	#fakeroot -s fakeroot.db dh_prep

	# Runs the build file.
	if [ -f "$recipe/build" ]
	then
		(
			ARCHITECTURE=$arch
			DESTDIR=$tmpdir/debian/$name
			NAME=$name
			RECIPE=$recipe
			VERSION=$vers
			export ARCHITECTURE DESTDIR NAME RECIPE VERSION

			mkdir --parents "$tmpdir/build"
			cd "$tmpdir/build"

			exec fakeroot \
				-i "$tmpdir/fakeroot.db" \
				-s "$tmpdir/fakeroot.db" \
				"$recipe/build"
		)
	fi

	fakeroot -i fakeroot.db -s fakeroot.db dh_installchangelogs
	fakeroot -i fakeroot.db -s fakeroot.db dh_compress
	fakeroot -i fakeroot.db -s fakeroot.db dh_fixperms
	fakeroot -i fakeroot.db -s fakeroot.db dh_installdeb
	cp --target-directory=debian/"$name"/DEBIAN debian/control #fakeroot -i fakeroot.db -s fakeroot.db dh_gencontrol
	fakeroot -i fakeroot.db -s fakeroot.db dh_md5sums
	mkdir --parents "$REPOSITORY"
	fakeroot -i fakeroot.db -s fakeroot.db dh_builddeb --destdir="$REPOSITORY"
	rm --force --recursive "$tmpdir"
)

# Refreshs the repository.
#
# refresh
refresh()
(
	cd "$REPOSITORY" \
		&& dpkg-scanpackages . | gzip > Packages.gz
)

################################################################################

if [ "${REPOSITORY:-}" ]
then
	psl=$REPOSITORY; psl_realpath; REPOSITORY=$psl
else
	REPOSITORY=$SCRIPT_DIR/repository
fi
