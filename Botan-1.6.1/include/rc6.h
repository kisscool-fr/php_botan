/*************************************************
* RC6 Header File                                *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#ifndef BOTAN_RC6_H__
#define BOTAN_RC6_H__

#include <botan/base.h>

namespace Botan {

/*************************************************
* RC6                                            *
*************************************************/
class RC6 : public BlockCipher
   {
   public:
      void clear() throw() { S.clear(); }
      std::string name() const { return "RC6"; }
      BlockCipher* clone() const { return new RC6; }
      RC6() : BlockCipher(16, 1, 32) {}
   private:
      void enc(const byte[], byte[]) const;
      void dec(const byte[], byte[]) const;
      void key(const byte[], u32bit);

      SecureBuffer<u32bit, 44> S;
   };

}

#endif
