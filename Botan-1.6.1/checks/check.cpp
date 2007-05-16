/*
 * Test Driver for Botan
 */

#include <vector>
#include <string>

#include <iostream>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>

#include <botan/botan.h>
#include <botan/mp_types.h>

using namespace Botan_types;

#include "getopt.h"

const std::string VALIDATION_FILE = "checks/validate.dat";
const std::string BIGINT_VALIDATION_FILE = "checks/mp_valid.dat";
const std::string PK_VALIDATION_FILE = "checks/pk_valid.dat";
const std::string EXPECTED_FAIL_FILE = "checks/fail.dat";

void benchmark(const std::string&, bool html, double seconds);
void bench_pk(const std::string&, bool html, double seconds);
u32bit bench_algo(const std::string&, double);
int validate();

int main(int argc, char* argv[])
   {
   try
      {
      OptionParser opts("help|html|init=|validate|"
                        "benchmark|bench-type=|bench-algo=|seconds=");
      opts.parse(argv);

      Botan::InitializerOptions init_options(opts.value_if_set("init"));
      Botan::LibraryInitializer init(init_options);

      if(opts.is_set("help") || argc <= 1)
         {
         std::cerr << Botan::version_string() << " test driver\n"
                   << "Options:\n"
                   << "  --validate: Check test vectors\n"
                   << "  --benchmark: Benchmark everything\n"
                   << "  --bench-type={block,mode,stream,hash,mac,rng,pk}:\n"
                   << "         Benchmark only algorithms of a particular type\n"
                   << "  --html: Produce HTML output for benchmarks\n"
                   << "  --seconds=n: Benchmark for n seconds\n"
                   << "  --help: Print this message\n";
         return 1;
         }

      if(opts.is_set("validate"))
         return validate();

      double seconds = 1.5;

      if(opts.is_set("seconds"))
         {
         seconds = std::atof(opts.value("seconds").c_str());
         if((seconds < 0.1 || seconds > 30) && seconds != 0)
            {
            std::cout << "Invalid argument to --seconds\n";
            return 2;
            }
         }

      const bool html = opts.is_set("html");

      if(opts.is_set("bench-algo"))
         {
         std::vector<std::string> algs =
            Botan::split_on(opts.value("bench-algo"), ',');

         for(u32bit j = 0; j != algs.size(); j++)
            {
            const std::string alg = algs[j];
            u32bit found = bench_algo(alg, seconds);
            if(!found) // maybe it's a PK algorithm
               bench_pk(alg, html, seconds);
            }
         }

      if(opts.is_set("benchmark"))
         benchmark("All", html, seconds);
      else if(opts.is_set("bench-type"))
         {
         const std::string type = opts.value("bench-type");

         if(type == "all")
            benchmark("All", html, seconds);
         else if(type == "block")
            benchmark("Block Cipher", html, seconds);
         else if(type == "stream")
            benchmark("Stream Cipher", html, seconds);
         else if(type == "hash")
            benchmark("Hash", html, seconds);
         else if(type == "mac")
            benchmark("MAC", html, seconds);
         else if(type == "rng")
            benchmark("RNG", html, seconds);
         else if(type == "pk")
            bench_pk("All", html, seconds);
         }
      }
   catch(Botan::Exception& e)
      {
      std::cout << "Exception caught:\n   " << e.what() << std::endl;
      return 1;
      }
   catch(std::exception& e)
      {
      std::cout << "Standard library exception caught:\n   "
                << e.what() << std::endl;
      return 1;
      }
   catch(...)
      {
      std::cout << "Unknown exception caught." << std::endl;
      return 1;
      }

   return 0;
   }

int validate()
   {
   void test_types();
   u32bit do_validation_tests(const std::string&, bool = true);
   u32bit do_bigint_tests(const std::string&);
   u32bit do_pk_validation_tests(const std::string&);

   std::cout << "Beginning validation tests..." << std::endl;

   test_types();
   u32bit errors = 0;
   try {
      errors += do_validation_tests(VALIDATION_FILE);
      errors += do_validation_tests(EXPECTED_FAIL_FILE, false);
      errors += do_bigint_tests(BIGINT_VALIDATION_FILE);
      errors += do_pk_validation_tests(PK_VALIDATION_FILE);
      }
   catch(Botan::Exception& e)
      {
      std::cout << "Exception caught: " << e.what() << std::endl;
      return 1;
      }
   catch(std::exception& e)
      {
      std::cout << "Standard library exception caught: "
                << e.what() << std::endl;
      return 1;
      }
   catch(...)
      {
      std::cout << "Unknown exception caught." << std::endl;
      return 1;
      }

   if(errors)
      {
      std::cout << errors << " test"  << ((errors == 1) ? "" : "s")
                << " failed." << std::endl;
      return 1;
      }

   std::cout << "All tests passed!" << std::endl;
   return 0;
   }

template<typename T>
bool test(const char* type, int digits, bool is_signed)
   {
   bool passed = true;
   if(std::numeric_limits<T>::is_specialized == false)
      {
      std::cout << "WARNING: Could not check parameters of " << type
                << " in std::numeric_limits" << std::endl;
      return true;
      }

   if(std::numeric_limits<T>::digits != digits && digits != 0)
      {
      std::cout << "ERROR: numeric_limits<" << type << ">::digits != "
                << digits << std::endl;
      passed = false;
      }
   if(std::numeric_limits<T>::is_signed != is_signed)
      {
      std::cout << "ERROR: numeric_limits<" << type << ">::is_signed != "
                << std::boolalpha << is_signed << std::endl;
      passed = false;
      }
   if(std::numeric_limits<T>::is_integer == false)
      {
      std::cout << "ERROR: numeric_limits<" << type
                << ">::is_integer == false " << std::endl;
      passed = false;
      }
   return passed;
   }

void test_types()
   {
   bool passed = true;

   passed = passed && test<Botan::byte  >("byte",    8, false);
   passed = passed && test<Botan::u16bit>("u16bit", 16, false);
   passed = passed && test<Botan::u32bit>("u32bit", 32, false);
   passed = passed && test<Botan::u64bit>("u64bit", 64, false);
   passed = passed && test<Botan::s32bit>("s32bit", 31,  true);
   passed = passed && test<Botan::word>("word", 0, false);

   if(!passed)
      {
      std::cout << "Important settings in types.h are wrong. Please fix "
                   "and recompile." << std::endl;
      std::exit(1);
      }
   }
