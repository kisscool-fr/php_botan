#ifndef PHP_BOTAN_H
#define PHP_BOTAN_H

#define PHP_BOTAN_EXTNAME "botan"
#define PHP_BOTAN_EXTVER "0.1"

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

extern "C" {
    #include "php.h"
}

#include <botan/botan.h>

PHP_FUNCTION(botan_version);

extern zend_module_entry botan_module_entry;
#define phpext_botan_ptr &botan_module_entry

#endif /* PHP_BOTAN_H */
