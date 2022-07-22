all:
	dart compile exe bin/arty.dart -o arty

run:
	dart run

install:
	@install -v arty ${HOME}/usr/bin
