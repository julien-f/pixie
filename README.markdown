This tool generates Debian packages from recipes and initializes Debian
repositories.


# Requirements

This tool requires a few programs to be installed in order to work correctly:

- `akula`
- `dpkg`
- `dpkg-dev`
- `fakeroot`

Please note that some of the “recipes” may have more dependencies (such as
`git`).


# Repository creation.

The `pixie build` command is used to build all the packages and to create the
repository.

For instance, if you want to make your packages available throught a web server:

	REPOSITORY=/var/www/repository
	pixie build "$REPOSITORY" recipes/*
	pixie refresh "$REPOSITORY"


# APT configuration.

Wondering what to put in your `/etc/apt/sources.list` to make your new packages
available to your system?

If the packages are directly available in the file system:

	deb file:/ABSOLUTE/PATH ./

If the repository is on a web server:

	deb http://HOSTNAME/RELATIVE/PATH/ ./


# What does a recipe look like?

A recipe is a directory named *`name`\_`version`\_`architecture`* which contains
all the necessary files for creating a package.

The first of these files is `control`, it contains various entries describing
the package.

A recipe MAY also contain a `build` program which will be called prior
constructing the package, its tasks are to:

- retrieve the source files;
- build them if necessary;
- install them in the `$DESTDIR` directory (an environment variable).

This program is runned in a temporary directory and should not bother cleaning
after itself. It also has access to its recipe directory through the `$RECIPE`
variable.

To create a new recipe, you may use the `pixie create` command which will ask
some information and then builds a valid skeleton (which is enough for basic
meta-packages).
