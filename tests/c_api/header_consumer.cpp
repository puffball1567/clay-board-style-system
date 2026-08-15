#include "cbss.h"

static_assert(CBSS_ABI_VERSION == 0x00010013u,
              "unexpected CBSS ABI version");

CBSS_DEPRECATED("compile-only C++ deprecation contract probe")
CBSS_API void deprecated_cpp_contract_probe(void);

int main() {
  return 0;
}
