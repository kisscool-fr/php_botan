/*************************************************
* OpenPGP S2K Source File                        *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#include <botan/pgp_s2k.h>
#include <botan/lookup.h>
#include <algorithm>
#include <memory>

namespace Botan {

/*************************************************
* Derive a key using the OpenPGP S2K algorithm   *
*************************************************/
OctetString OpenPGP_S2K::derive(u32bit key_len, const std::string& passphrase,
                                const byte salt_buf[], u32bit salt_size,
                                u32bit iterations) const
   {
   SecureVector<byte> key(key_len), hash_buf;

   u32bit pass = 0, generated = 0,
          total_size = passphrase.size() + salt_size;
   u32bit to_hash = std::max(iterations, total_size);

   std::auto_ptr<HashFunction> hash(get_hash(hash_name));

   hash->clear();
   while(key_len > generated)
      {
      for(u32bit j = 0; j != pass; ++j)
         hash->update(0);

      u32bit left = to_hash;
      while(left >= total_size)
         {
         hash->update(salt_buf, salt_size);
         hash->update(passphrase);
         left -= total_size;
         }
      if(left <= salt_size)
         hash->update(salt_buf, left);
      else
         {
         hash->update(salt_buf, salt_size);
         left -= salt_size;
         hash->update((const byte*)passphrase.c_str(), left);
         }

      hash_buf = hash->final();
      key.copy(generated, hash_buf, hash->OUTPUT_LENGTH);
      generated += hash->OUTPUT_LENGTH;
      ++pass;
      }

   return key;
   }

/*************************************************
* Return the name of this type                   *
*************************************************/
std::string OpenPGP_S2K::name() const
   {
   return "OpenPGP-S2K(" + hash_name + ")";
   }

/*************************************************
* Return a clone of this object                  *
*************************************************/
S2K* OpenPGP_S2K::clone() const
   {
   return new OpenPGP_S2K(hash_name);
   }

/*************************************************
* OpenPGP S2K Constructor                        *
*************************************************/
OpenPGP_S2K::OpenPGP_S2K(const std::string& h) : hash_name(h)
   {
   }

}
