/*************************************************
* HAS-160 Header File                            *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#ifndef BOTAN_HAS_160_H__
#define BOTAN_HAS_160_H__

#include <botan/mdx_hash.h>

namespace Botan {

/*************************************************
* HAS-160                                        *
*************************************************/
class HAS_160 : public MDx_HashFunction
   {
   public:
      void clear() throw();
      std::string name() const { return "HAS-160"; }
      HashFunction* clone() const { return new HAS_160; }
      HAS_160() : MDx_HashFunction(20, 64, false, true) { clear(); }
   private:
      void hash(const byte[]);
      void copy_out(byte[]);

      SecureBuffer<u32bit, 20> X;
      SecureBuffer<u32bit, 5> digest;
   };

}

#endif
