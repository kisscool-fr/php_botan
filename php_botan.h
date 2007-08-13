#ifndef PHP_BOTAN_H
#define PHP_BOTAN_H 1

#define PHP_BOTAN_VERSION "0.1"
#define PHP_BOTAN_EXTNAME "botan"

PHP_FUNCTION(botan_version);

extern zend_module_entry botan_module_entry;
#define phpext_botan_ptr &botan_module_entry

#endif
