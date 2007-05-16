/*************************************************
* CMAC Source File                               *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#include <botan/cmac.h>
#include <botan/lookup.h>
#include <botan/bit_ops.h>

namespace Botan {

namespace {

/*************************************************
* Perform CMAC's multiplication in GF(2^n)       *
*************************************************/
SecureVector<byte> poly_double(const MemoryRegion<byte>& in, byte polynomial)
   {
   const bool do_xor = (in[0] & 0x80) ? true : false;

   SecureVector<byte> out = in;

   byte carry = 0;
   for(u32bit j = out.size(); j != 0; --j)
      {
      byte temp = out[j-1];
      out[j-1] = (temp << 1) | carry;
      carry = (temp >> 7);
      }

   if(do_xor)
      out[out.size()-1] ^= polynomial;

   return out;
   }

}

/*************************************************
* Update an CMAC Calculation                     *
*************************************************/
void CMAC::add_data(const byte input[], u32bit length)
   {
   buffer.copy(position, input, length);
   if(position + length > OUTPUT_LENGTH)
      {
      xor_buf(state, buffer, OUTPUT_LENGTH);
      e->encrypt(state);
      input += (OUTPUT_LENGTH - position);
      length -= (OUTPUT_LENGTH - position);
      while(length > OUTPUT_LENGTH)
         {
         xor_buf(state, input, OUTPUT_LENGTH);
         e->encrypt(state);
         input += OUTPUT_LENGTH;
         length -= OUTPUT_LENGTH;
         }
      buffer.copy(input, length);
      position = 0;
      }
   position += length;
   }

/*************************************************
* Finalize an CMAC Calculation                   *
*************************************************/
void CMAC::final_result(byte mac[])
   {
   if(position == OUTPUT_LENGTH)
      xor_buf(buffer, B, OUTPUT_LENGTH);
   else
      {
      buffer[position] = 0x80;
      for(u32bit j = position+1; j != OUTPUT_LENGTH; ++j)
         buffer[j] = 0;
      xor_buf(buffer, P, OUTPUT_LENGTH);
      }
   xor_buf(state, buffer, OUTPUT_LENGTH);
   e->encrypt(state);

   for(u32bit j = 0; j != OUTPUT_LENGTH; ++j)
      mac[j] = state[j];

   state.clear();
   buffer.clear();
   position = 0;
   }

/*************************************************
* CMAC Key Schedule                              *
*************************************************/
void CMAC::key(const byte key[], u32bit length)
   {
   clear();
   e->set_key(key, length);
   e->encrypt(B);
   B = poly_double(B, polynomial);
   P = poly_double(B, polynomial);
   }

/*************************************************
* Clear memory of sensitive data                 *
*************************************************/
void CMAC::clear() throw()
   {
   e->clear();
   state.clear();
   buffer.clear();
   B.clear();
   P.clear();
   position = 0;
   }

/*************************************************
* Return the name of this type                   *
*************************************************/
std::string CMAC::name() const
   {
   return "CMAC(" + e->name() + ")";
   }

/*************************************************
* Return a clone of this object                  *
*************************************************/
MessageAuthenticationCode* CMAC::clone() const
   {
   return new CMAC(e->name());
   }

/*************************************************
* CMAC Constructor                               *
*************************************************/
CMAC::CMAC(const std::string& bc_name) :
   MessageAuthenticationCode(block_size_of(bc_name),
                             min_keylength_of(bc_name),
                             max_keylength_of(bc_name),
                             keylength_multiple_of(bc_name))
   {
   e = get_block_cipher(bc_name);

   if(e->BLOCK_SIZE == 16)     polynomial = 0x87;
   else if(e->BLOCK_SIZE == 8) polynomial = 0x1B;
   else
      throw Invalid_Argument("CMAC cannot use the cipher " + e->name());

   state.create(OUTPUT_LENGTH);
   buffer.create(OUTPUT_LENGTH);
   B.create(OUTPUT_LENGTH);
   P.create(OUTPUT_LENGTH);
   position = 0;
   }

}
