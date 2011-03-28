#include "php_botan.h"

static function_entry botan_functions[] = {
	PHP_FE(botan_version, NULL)
	{NULL, NULL, NULL}
};

PHP_MINIT_FUNCTION(botan)
{
    return SUCCESS;
}

zend_module_entry botan_module_entry = {
#if ZEND_MODULE_API_NO >= 20010901
	STANDARD_MODULE_HEADER,
#endif
	PHP_BOTAN_EXTNAME,
	botan_functions,
	PHP_MINIT(botan),
	NULL,
	NULL,
	NULL,
	NULL,
#if ZEND_MODULE_API_NO >= 20010901
	PHP_BOTAN_EXTVER,
#endif
	STANDARD_MODULE_PROPERTIES
};

#ifdef COMPILE_DL_BOTAN
extern "C" {
    ZEND_GET_MODULE(botan)
}
#endif

PHP_FUNCTION(botan_version)
{
	Botan::LibraryInitializer init("thread_safe=yes");
	/* now do stuff */

	RETURN_STRING(PHP_BOTAN_EXTVER, 1);
}
