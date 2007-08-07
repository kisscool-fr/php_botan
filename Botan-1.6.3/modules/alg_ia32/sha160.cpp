/*************************************************
* SHA-160 Source File                            *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#include <botan/sha160.h>
#include <botan/bit_ops.h>

namespace Botan {

extern "C" void sha160_core(u32bit[5], const byte[64], u32bit[81]);

/*************************************************
* SHA-160 Compression Function                   *
*************************************************/
void SHA_160::hash(const byte input[])
   {
   sha160_core(digest, input, W);
   }

/*************************************************
* Copy out the digest                            *
*************************************************/
void SHA_160::copy_out(byte output[])
   {
   for(u32bit j = 0; j != OUTPUT_LENGTH; ++j)
      output[j] = get_byte(j % 4, digest[j/4]);
   }

/*************************************************
* Clear memory of sensitive data                 *
*************************************************/
void SHA_160::clear() throw()
   {
   MDx_HashFunction::clear();
   W.clear();
   digest[0] = 0x67452301;
   digest[1] = 0xEFCDAB89;
   digest[2] = 0x98BADCFE;
   digest[3] = 0x10325476;
   digest[4] = 0xC3D2E1F0;
   }

/*************************************************
* SHA_160 Constructor                            *
*************************************************/
SHA_160::SHA_160() : MDx_HashFunction(20, 64, true, true), W(81)
   {
   clear();
   }

}
