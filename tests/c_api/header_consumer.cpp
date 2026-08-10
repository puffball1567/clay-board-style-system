#include "cbss.h"

static_assert(CBSS_ABI_VERSION == 0x0001000Fu,
              "unexpected CBSS ABI version");

CBSS_DEPRECATED("compile-only C++ deprecation contract probe")
CBSS_API void deprecated_cpp_contract_probe(void);

int main() {
  return 0;
}
