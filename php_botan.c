#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <botan/botan.h>

#include "php.h"
#include "php_botan.h"

static function_entry botan_functions[] = {
	PHP_FE(botan_version, NULL)
	{NULL, NULL, NULL}
};

zend_module_entry botan_module_entry = {
#if ZEND_MODULE_API_NO >= 20010901
	STANDARD_MODULE_HEADER,
#endif
	PHP_BOTAN_EXTNAME,
	botan_functions,
	NULL,
	NULL,
	NULL,
	NULL,
	NULL,
#if ZEND_MODULE_API_NO >= 20010901
	PHP_BOTAN_VERSION,
#endif
	STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_BOTAN
ZEND_GET_MODULE(botan)
#endif

PHP_FUNCTION(botan_version)
{
	LibraryInitializer init;
	/* now do stuff */

	RETURN_STRING(PHP_BOTAN_VERSION, 1);
}
