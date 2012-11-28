[ "$COMMON_SH" ] && return
COMMON_SH=1

################################################################################

# Fatal error if an untested command failed or if an
# undefined variable is used.
set -e -u

#
if [ "$AKULA_COMMAND" ]
then
	COMMAND="$AKULA_COMMAND $AKULA_SUBCOMMAND"
else
	COMMAND=${0##*/}
fi

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

# Splits a full package name to its components.
#
# A full package name has the following format: NAME[_ARCHITURE].
#
# If there is no “_ARCHITECTURE” part, the architecture is set to “all”.
#
# split_pkg_name PACKAGE @NAME @ARCHITECTURE
split_pkg_name()
{
	$psl_local psl

	IFS=_ read -r "$2" psl <<EOF
$1
EOF

	# Sets a default value for the architecture.
	: ${psl:=all}

	# Assigns this value to the variable named "$3".
	psl_set_value "$3"
}

# Builds a package from a recipe.
#
# build <recipe> <repository>
build()
(
	$psl_local \
		psl \
		recipe \
		name vers arch \
		workdir builddir dhdir tmpdir \
		fakerootdb

	psl=$1; psl_realpath; recipe=$psl
	psl_basename; split_pkg_name "$psl" name arch
	read vers < "$recipe"/@version
	psl=$2; psl_realpath; repository=$psl

	[ -f "$recipe"/@control ] \
		|| psl_fatal "not a valid recipe: $recipe"
	[ -d "$repository" ] \
		|| psl_fatal "not a valid directory: $repository"

	# Creation of the temporary working directory.
	workdir=$(mktemp --directory)

	# Build directory.
	builddir=$workdir/debian/$name
	mkdir --parents "$builddir"

	# Debhelper directory.
	dhdir=$workdir/debian
	mkdir --parents "$dhdir"
	psl_println 9 > "$dhdir"/compat

	# Creation of the control file.
	{
		# Adds automatic entries.
		psl_println \
			"Package:      $name" \
			"Version:      $vers" \
			"Architecture: $arch"

		# Removes comments and blank lines.
		cat "$recipe"/@control | perl -ne 's/^#.*//; print unless /^$/'
	} > "$dhdir"/control

	# Copy or creation of the changelog.
	if [ -f "$recipe"/@changelog ]
	then
		cp --target-directory="$dhdir" "$recipe"/@changelog
	else
		DATE=$(date --rfc-2822) \
			PACKAGE=$name \
			VERSION=$vers \
			USERNAME=Nobody \
			EMAIL=nobody@nowhere.tld \
			configure < "$SCRIPT_DIR"/../resources/changelog.in > "$dhdir"/changelog
	fi

	# Create the Fakeroot database.
	fakerootdb=$workdir/fakeroot.db
	touch "$fakerootdb"

	# Runs the build program.
	if [ -f "$recipe"/@build ]
	then
		tmpdir=$workdir/tmp
		mkdir "$tmpdir"
		cd "$tmpdir"

		ARCHITECTURE=$arch \
			DESTDIR=$builddir \
			NAME=$name \
			RECIPE=$recipe \
			VERSION=$vers \
			fakeroot -i "$fakerootdb" -s "$fakerootdb" "$recipe"/@build
	fi

	cd "$workdir"

	fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_installchangelogs
	fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_compress
	fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_fixperms
	fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_installdeb


	#fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_gencontrol
	cp --target-directory="$dhdir/$name"/DEBIAN "$dhdir"/control

	fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_md5sums
	fakeroot -i "$fakerootdb" -s "$fakerootdb" dh_builddeb --destdir="$repository"

	rm --force --recursive "$tmpdir"
)

# Refreshs the repository.
#
# refresh REPOSITORY.
refresh()
(
	cd "$1" \
		&& dpkg-scanpackages . | gzip > Packages.gz
)
