/*************************************************
* GNU MP Memory Handlers Source File             *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#include <botan/eng_gmp.h>
#include <cstring>
#include <gmp.h>

namespace Botan {

namespace {

/*************************************************
* Allocator used by GNU MP                       *
*************************************************/
Allocator* gmp_alloc = 0;

/*************************************************
* Allocation Function for GNU MP                 *
*************************************************/
void* gmp_malloc(size_t n)
   {
   return gmp_alloc->allocate(n);
   }

/*************************************************
* Reallocation Function for GNU MP               *
*************************************************/
void* gmp_realloc(void* ptr, size_t old_n, size_t new_n)
   {
   void* new_buf = gmp_alloc->allocate(new_n);
   std::memcpy(new_buf, ptr, std::min(old_n, new_n));
   gmp_alloc->deallocate(ptr, old_n);
   return new_buf;
   }

/*************************************************
* Deallocation Function for GNU MP               *
*************************************************/
void gmp_free(void* ptr, size_t n)
   {
   gmp_alloc->deallocate(ptr, n);
   }

}

/*************************************************
* Set the GNU MP memory functions                *
*************************************************/
void GMP_Engine::set_memory_hooks()
   {
   if(gmp_alloc == 0)
      {
      gmp_alloc = Allocator::get(true);
      mp_set_memory_functions(gmp_malloc, gmp_realloc, gmp_free);
      }
   }

}
