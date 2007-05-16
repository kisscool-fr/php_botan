/*************************************************
* Blowfish Source File                           *
* (C) 1999-2007 The Botan Project                *
*************************************************/

#include <botan/blowfish.h>
#include <botan/bit_ops.h>

namespace Botan {

/*************************************************
* Blowfish Encryption                            *
*************************************************/
void Blowfish::enc(const byte in[], byte out[]) const
   {
   u32bit L = make_u32bit(in[0], in[1], in[2], in[3]),
          R = make_u32bit(in[4], in[5], in[6], in[7]);

   for(u32bit j = 0; j != 16; j += 2)
      {
      L ^= P[j];
      R ^= ((S1[get_byte(0, L)]  + S2[get_byte(1, L)]) ^
             S3[get_byte(2, L)]) + S4[get_byte(3, L)];

      R ^= P[j+1];
      L ^= ((S1[get_byte(0, R)]  + S2[get_byte(1, R)]) ^
             S3[get_byte(2, R)]) + S4[get_byte(3, R)];
      }

   L ^= P[16]; R ^= P[17];

   out[0] = get_byte(0, R); out[1] = get_byte(1, R);
   out[2] = get_byte(2, R); out[3] = get_byte(3, R);
   out[4] = get_byte(0, L); out[5] = get_byte(1, L);
   out[6] = get_byte(2, L); out[7] = get_byte(3, L);
   }

/*************************************************
* Blowfish Decryption                            *
*************************************************/
void Blowfish::dec(const byte in[], byte out[]) const
   {
   u32bit L = make_u32bit(in[0], in[1], in[2], in[3]),
          R = make_u32bit(in[4], in[5], in[6], in[7]);

   for(u32bit j = 17; j != 1; j -= 2)
      {
      L ^= P[j];
      R ^= ((S1[get_byte(0, L)]  + S2[get_byte(1, L)]) ^
             S3[get_byte(2, L)]) + S4[get_byte(3, L)];

      R ^= P[j-1];
      L ^= ((S1[get_byte(0, R)]  + S2[get_byte(1, R)]) ^
             S3[get_byte(2, R)]) + S4[get_byte(3, R)];
      }

   L ^= P[1]; R ^= P[0];

   out[0] = get_byte(0, R); out[1] = get_byte(1, R);
   out[2] = get_byte(2, R); out[3] = get_byte(3, R);
   out[4] = get_byte(0, L); out[5] = get_byte(1, L);
   out[6] = get_byte(2, L); out[7] = get_byte(3, L);
   }

/*************************************************
* Blowfish Key Schedule                          *
*************************************************/
void Blowfish::key(const byte key[], u32bit length)
   {
   clear();
   for(u32bit j = 0, k = 0; j != 18; ++j, k += 4)
      P[j] ^= make_u32bit(key[(k  ) % length], key[(k+1) % length],
                             key[(k+2) % length], key[(k+3) % length]);
   u32bit L = 0, R = 0;
   generate_sbox(P,  18,  L, R);
   generate_sbox(S1, 256, L, R);
   generate_sbox(S2, 256, L, R);
   generate_sbox(S3, 256, L, R);
   generate_sbox(S4, 256, L, R);
   }

/*************************************************
* Generate one of the Sboxes                     *
*************************************************/
void Blowfish::generate_sbox(u32bit Box[], u32bit size,
                             u32bit& L, u32bit& R) const
   {
   for(u32bit j = 0; j != size; j += 2)
      {
      for(u32bit k = 0; k != 16; k += 2)
         {
         L ^= P[k];
         R ^= ((S1[get_byte(0, L)]  + S2[get_byte(1, L)]) ^
                S3[get_byte(2, L)]) + S4[get_byte(3, L)];

         R ^= P[k+1];
         L ^= ((S1[get_byte(0, R)]  + S2[get_byte(1, R)]) ^
                S3[get_byte(2, R)]) + S4[get_byte(3, R)];
         }

      u32bit T = R; R = L ^ P[16]; L = T ^ P[17];
      Box[j] = L; Box[j+1] = R;
      }
   }

/*************************************************
* Clear memory of sensitive data                 *
*************************************************/
void Blowfish::clear() throw()
   {
   P.copy(PBOX, 18);
   S1.copy(SBOX1, 256);
   S2.copy(SBOX2, 256);
   S3.copy(SBOX3, 256);
   S4.copy(SBOX4, 256);
   }

}
