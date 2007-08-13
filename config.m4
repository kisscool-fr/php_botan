PHP_ARG_ENABLE(botan, whether to enable Botan Cryptographic Library support, [ --enable-botan Enable Botan support])

if test "$PHP_BOTAN" = "yes"; then
	AC_DEFINE(HAVE_BOTAN, 1, [Whether you have Botan])
	PHP_NEW_EXTENSION(botan, php_botan.c, $ext_shared)
fi
