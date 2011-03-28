PHP_ARG_ENABLE(botan,
    [whether to enable Botan Cryptographic Library support],
    [ --enable-botan Enable Botan support]
)

if test $PHP_BOTAN != "no"; then
    PHP_REQUIRE_CXX()
    PHP_SUBST(BOTAN_SHARED_LIBADD)
    PHP_ADD_LIBRARY(stdc++, 1, BOTAN_SHARED_LIBRARY)
	PHP_NEW_EXTENSION(botan, php_botan.cc, $ext_shared)
fi
