#include "cbss.h"

#ifndef CBSS_DEPRECATED
#error "CBSS_DEPRECATED must be provided by the public header"
#endif

CBSS_DEPRECATED("compile-only C deprecation contract probe")
CBSS_API void deprecated_c_contract_probe(void);

int main(void) {
  return CBSS_ABI_VERSION == 0x0001000Eu ? 0 : 1;
}
