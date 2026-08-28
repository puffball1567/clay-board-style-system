#ifndef CBSS_VALIDATION_HPP
#define CBSS_VALIDATION_HPP

#include "cbss.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <functional>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

namespace cbss {

enum class ValidationReport { onInput, onBlur, onSubmit };
enum class ValidationTrigger { input, blur, submit, explicitCheck };

enum class ValidationRuleKind {
  required, optional, minLength, maxLength, exactLength, notBlank, matches,
  contains, startsWith, endsWith, email, url, uuid, ipAddress, date, time,
  dateTime, min, max, range, integer, positive, negative, finite, multipleOf,
  equalTo, notEqualTo, oneOf, notOneOf, sameAs, differentFrom, minItems,
  maxItems, exactItems, uniqueItems, maxFileSize, allowedMimeTypes,
  allowedExtensions, maxFiles, custom
};

inline const char* validationRuleCode(ValidationRuleKind kind) {
  static const char* codes[] = {
      "required", "optional", "minLength", "maxLength", "exactLength",
      "notBlank", "matches", "contains", "startsWith", "endsWith",
      "email", "url", "uuid", "ipAddress", "date", "time", "dateTime",
      "min", "max", "range", "integer", "positive", "negative", "finite",
      "multipleOf", "equalTo", "notEqualTo", "oneOf", "notOneOf",
      "sameAs", "differentFrom", "minItems", "maxItems", "exactItems",
      "uniqueItems", "maxFileSize", "allowedMimeTypes",
      "allowedExtensions", "maxFiles", "custom"};
  return codes[static_cast<std::size_t>(kind)];
}

struct ValidationIssue {
  std::string code;
  std::string message;
  int ruleIndex = -1;
};

struct ValidationResult {
  bool isValid = true;
  ValidationIssue issue;

  static ValidationResult valid() { return ValidationResult{}; }
  static ValidationResult invalid(ValidationRuleKind kind,
                                  const std::string& message, int index) {
    ValidationResult result;
    result.isValid = false;
    result.issue = {validationRuleCode(kind), message, index};
    return result;
  }
};

struct ValidationFile {
  std::string name;
  std::string mimeType;
  std::uint64_t size = 0;
};

class ValidationPattern {
 public:
  explicit ValidationPattern(const std::string& source) {
    if (source.size() > CBSS_MAX_VALIDATION_PATTERN_BYTES) {
      throw std::invalid_argument("validation regular expression is too large");
    }
    char error[512] = {};
    CbssValidationPattern* value = nullptr;
    const CbssStatus status = cbss_validation_pattern_compile(
        source.data(), static_cast<std::uint32_t>(source.size()), &value,
        error, static_cast<std::uint32_t>(sizeof(error)));
    if (status != CBSS_OK || value == nullptr) {
      throw std::invalid_argument(error[0] == '\0'
          ? "invalid validation regular expression" : error);
    }
    handle_.reset(value, cbss_validation_pattern_destroy);
  }

  bool test(const std::string& value) const {
    if (value.size() > CBSS_MAX_VALIDATION_VALUE_BYTES) {
      return false;
    }
    std::uint8_t matched = 0;
    const void* bytes = value.empty() ? nullptr : value.data();
    const CbssStatus status = cbss_validation_pattern_matches(
        handle_.get(), bytes, static_cast<std::uint32_t>(value.size()),
        &matched);
    if (status != CBSS_OK) {
      throw std::runtime_error("unable to evaluate validation pattern");
    }
    return matched != 0;
  }

 private:
  std::shared_ptr<CbssValidationPattern> handle_;
};

template <typename T>
class ValidationValue {
 public:
  explicit ValidationValue(T value)
      : value_(std::make_shared<T>(std::move(value))) {}
  const T& get() const { return *value_; }
  void set(T value) { *value_ = std::move(value); }
  const void* identity() const noexcept { return value_.get(); }

 private:
  explicit ValidationValue(std::shared_ptr<T> value) : value_(std::move(value)) {}
  std::shared_ptr<T> value_;
  template <typename U> friend class ValidationRules;
};

namespace validation_detail {

template <typename T> struct Traits {
  static bool absent(const T&) { return false; }
  static int length(const T&) { return -1; }
};

template <> struct Traits<std::string> {
  static bool absent(const std::string& value) { return value.empty(); }
  static int length(const std::string& value) {
    int count = 0;
    for (unsigned char byte : value) {
      if ((byte & 0xc0u) != 0x80u) ++count;
    }
    return count;
  }
};

template <typename T> struct Traits<std::vector<T>> {
  static bool absent(const std::vector<T>& value) { return value.empty(); }
  static int length(const std::vector<T>& value) {
    return static_cast<int>(value.size());
  }
};

inline std::string trimLower(std::string value) {
  const std::string whitespace = " \t\r\n";
  const std::size_t first = value.find_first_not_of(whitespace);
  if (first == std::string::npos) return "";
  const std::size_t last = value.find_last_not_of(whitespace);
  value = value.substr(first, last - first + 1);
  std::transform(value.begin(), value.end(), value.begin(),
      [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
  return value;
}

inline bool stringFormat(CbssValidationStringFormat format,
                         const std::string& value) {
  if (value.size() > CBSS_MAX_VALIDATION_VALUE_BYTES) return false;
  std::uint8_t valid = 0;
  const void* bytes = value.empty() ? nullptr : value.data();
  const CbssStatus status = cbss_validation_string_format(
      format, bytes, static_cast<std::uint32_t>(value.size()), &valid);
  if (status != CBSS_OK) {
    throw std::runtime_error("unable to evaluate validation format");
  }
  return valid != 0;
}

inline std::string extensionOf(const std::string& name) {
  const std::size_t dot = name.find_last_of('.');
  if (dot == std::string::npos || dot + 1 >= name.size()) return "";
  return trimLower(name.substr(dot + 1));
}

inline bool mimeAllowed(const std::string& input,
                        const std::vector<std::string>& allowed) {
  const std::string value = trimLower(input);
  for (const std::string& candidate : allowed) {
    if (candidate == "*/*") return true;
    if (candidate.size() >= 2 &&
        candidate.compare(candidate.size() - 2, 2, "/*") == 0 &&
        value.compare(0, candidate.size() - 1,
                      candidate, 0, candidate.size() - 1) == 0) return true;
    if (candidate == value) return true;
  }
  return false;
}

}  // namespace validation_detail

template <typename T>
class ValidationRules {
  struct Rule {
    ValidationRuleKind kind;
    std::string message;
    std::function<bool(const T&)> test;
    std::shared_ptr<T> peer;
  };

 public:
  std::size_t size() const noexcept { return rules_.size(); }

  ValidationRules required(std::string message = "This value is required") const {
    return add(ValidationRuleKind::required, std::move(message),
        [](const T& value) { return !validation_detail::Traits<T>::absent(value); });
  }
  ValidationRules optional() const {
    return add(ValidationRuleKind::optional, "", [](const T&) { return true; });
  }
  ValidationRules minLength(int length, std::string message = "Value is too short") const {
    requireNonNegative(length, "minimum length");
    return add(ValidationRuleKind::minLength, std::move(message),
        [length](const T& value) { return validation_detail::Traits<T>::length(value) >= length; });
  }
  ValidationRules maxLength(int length, std::string message = "Value is too long") const {
    requireNonNegative(length, "maximum length");
    return add(ValidationRuleKind::maxLength, std::move(message), [length](const T& value) {
      const int size = validation_detail::Traits<T>::length(value);
      return size >= 0 && size <= length;
    });
  }
  ValidationRules exactLength(int length, std::string message = "Value has the wrong length") const {
    requireNonNegative(length, "exact length");
    return add(ValidationRuleKind::exactLength, std::move(message),
        [length](const T& value) { return validation_detail::Traits<T>::length(value) == length; });
  }
  ValidationRules notBlank(std::string message = "Value cannot be blank") const {
    return add(ValidationRuleKind::notBlank, std::move(message), [](const T& value) {
      return !validation_detail::trimLower(value).empty();
    });
  }
  ValidationRules matches(ValidationPattern pattern,
                          std::string message = "Value has an invalid format") const {
    return add(ValidationRuleKind::matches, std::move(message),
        [pattern](const T& value) { return pattern.test(value); });
  }
  ValidationRules contains(std::string text,
                           std::string message = "Value does not contain the required text") const {
    return add(ValidationRuleKind::contains, std::move(message),
        [text](const T& value) { return value.find(text) != std::string::npos; });
  }
  ValidationRules startsWith(std::string text,
                             std::string message = "Value has the wrong prefix") const {
    return add(ValidationRuleKind::startsWith, std::move(message), [text](const T& value) {
      return value.size() >= text.size() && value.compare(0, text.size(), text) == 0;
    });
  }
  ValidationRules endsWith(std::string text,
                           std::string message = "Value has the wrong suffix") const {
    return add(ValidationRuleKind::endsWith, std::move(message), [text](const T& value) {
      return value.size() >= text.size() &&
          value.compare(value.size() - text.size(), text.size(), text) == 0;
    });
  }

#define CBSS_STRING_FORMAT_METHOD(name, enumValue, defaultMessage)             \
  ValidationRules name(std::string message = defaultMessage) const {           \
    return add(ValidationRuleKind::name, std::move(message),                   \
        [](const T& value) { return validation_detail::stringFormat(           \
            enumValue, value); });                                             \
  }
  CBSS_STRING_FORMAT_METHOD(email, CBSS_VALIDATION_FORMAT_EMAIL,
      "Value is not a valid email address")
  CBSS_STRING_FORMAT_METHOD(url, CBSS_VALIDATION_FORMAT_URL,
      "Value is not a valid URL")
  CBSS_STRING_FORMAT_METHOD(uuid, CBSS_VALIDATION_FORMAT_UUID,
      "Value is not a valid UUID")
  CBSS_STRING_FORMAT_METHOD(ipAddress, CBSS_VALIDATION_FORMAT_IP_ADDRESS,
      "Value is not a valid IP address")
  CBSS_STRING_FORMAT_METHOD(date, CBSS_VALIDATION_FORMAT_DATE,
      "Value is not a valid date")
  CBSS_STRING_FORMAT_METHOD(time, CBSS_VALIDATION_FORMAT_TIME,
      "Value is not a valid time")
  CBSS_STRING_FORMAT_METHOD(dateTime, CBSS_VALIDATION_FORMAT_DATE_TIME,
      "Value is not a valid date and time")
#undef CBSS_STRING_FORMAT_METHOD

  ValidationRules min(T limit, std::string message = "Value is below the minimum") const {
    requireOrderedLimit(limit);
    return add(ValidationRuleKind::min, std::move(message),
        [limit](const T& value) { return value >= limit; });
  }
  ValidationRules max(T limit, std::string message = "Value exceeds the maximum") const {
    requireOrderedLimit(limit);
    return add(ValidationRuleKind::max, std::move(message),
        [limit](const T& value) { return value <= limit; });
  }
  ValidationRules range(T minimum, T maximum,
                         std::string message = "Value is outside the allowed range") const {
    requireOrderedLimit(minimum); requireOrderedLimit(maximum);
    if (minimum > maximum) throw std::invalid_argument("validation range minimum cannot exceed maximum");
    return add(ValidationRuleKind::range, std::move(message),
        [minimum, maximum](const T& value) { return value >= minimum && value <= maximum; });
  }
  ValidationRules integer(std::string message = "Value must be an integer") const {
    return add(ValidationRuleKind::integer, std::move(message), [](const T& value) {
      return std::is_integral<T>::value ||
          (std::isfinite(static_cast<double>(value)) &&
           std::floor(static_cast<double>(value)) == static_cast<double>(value));
    });
  }
  ValidationRules positive(std::string message = "Value must be positive") const {
    return add(ValidationRuleKind::positive, std::move(message),
        [](const T& value) { return value > T(0); });
  }
  ValidationRules negative(std::string message = "Value must be negative") const {
    return add(ValidationRuleKind::negative, std::move(message),
        [](const T& value) { return value < T(0); });
  }
  ValidationRules finite(std::string message = "Value must be finite") const {
    return add(ValidationRuleKind::finite, std::move(message),
        [](const T& value) { return std::isfinite(static_cast<double>(value)); });
  }
  ValidationRules multipleOf(T divisor,
                              std::string message = "Value is not an allowed multiple") const {
    requireFiniteDivisor(divisor);
    if (static_cast<double>(divisor) == 0.0)
      throw std::invalid_argument("multipleOf divisor cannot be zero");
    return add(ValidationRuleKind::multipleOf, std::move(message), [divisor](const T& value) {
      const double quotient = static_cast<double>(value) /
                              static_cast<double>(divisor);
      return std::isfinite(quotient) &&
          std::fabs(quotient - std::round(quotient)) <=
              1.0e-9 * std::max(1.0, std::fabs(quotient));
    });
  }
  ValidationRules equalTo(T expected,
                           std::string message = "Value does not match the expected value") const {
    return add(ValidationRuleKind::equalTo, std::move(message),
        [expected](const T& value) { return value == expected; });
  }
  ValidationRules notEqualTo(T expected,
                              std::string message = "Value must differ from the rejected value") const {
    return add(ValidationRuleKind::notEqualTo, std::move(message),
        [expected](const T& value) { return value != expected; });
  }
  ValidationRules oneOf(std::vector<T> values,
                         std::string message = "Value is not an allowed choice") const {
    return add(ValidationRuleKind::oneOf, std::move(message), [values](const T& value) {
      return std::find(values.begin(), values.end(), value) != values.end();
    });
  }
  ValidationRules notOneOf(std::vector<T> values,
                            std::string message = "Value is a rejected choice") const {
    return add(ValidationRuleKind::notOneOf, std::move(message), [values](const T& value) {
      return std::find(values.begin(), values.end(), value) == values.end();
    });
  }
  ValidationRules sameAs(ValidationValue<T> peer,
                          std::string message = "Values do not match") const {
    ValidationRules result = add(ValidationRuleKind::sameAs, std::move(message),
        [peer](const T& value) { return value == peer.get(); });
    result.rules_.back().peer = peer.value_;
    return result;
  }
  ValidationRules differentFrom(ValidationValue<T> peer,
                                 std::string message = "Values must differ") const {
    ValidationRules result = add(ValidationRuleKind::differentFrom, std::move(message),
        [peer](const T& value) { return value != peer.get(); });
    result.rules_.back().peer = peer.value_;
    return result;
  }
  ValidationRules minItems(int count, std::string message = "Too few items are selected") const {
    requireNonNegative(count, "minimum item count");
    return add(ValidationRuleKind::minItems, std::move(message),
        [count](const T& value) { return static_cast<int>(value.size()) >= count; });
  }
  ValidationRules maxItems(int count, std::string message = "Too many items are selected") const {
    requireNonNegative(count, "maximum item count");
    return add(ValidationRuleKind::maxItems, std::move(message),
        [count](const T& value) { return static_cast<int>(value.size()) <= count; });
  }
  ValidationRules exactItems(int count, std::string message = "The wrong number of items is selected") const {
    requireNonNegative(count, "exact item count");
    return add(ValidationRuleKind::exactItems, std::move(message),
        [count](const T& value) { return static_cast<int>(value.size()) == count; });
  }
  ValidationRules uniqueItems(std::string message = "Items must be unique") const {
    return add(ValidationRuleKind::uniqueItems, std::move(message), [](const T& value) {
      for (std::size_t first = 0; first < value.size(); ++first)
        for (std::size_t second = first + 1; second < value.size(); ++second)
          if (value[first] == value[second]) return false;
      return true;
    });
  }
  ValidationRules maxFileSize(std::uint64_t bytes,
                              std::string message = "A file exceeds the size limit") const {
    return add(ValidationRuleKind::maxFileSize, std::move(message), [bytes](const T& files) {
      for (const auto& file : files) if (file.size > bytes) return false;
      return true;
    });
  }
  ValidationRules allowedMimeTypes(std::vector<std::string> values,
                                    std::string message = "A file has a disallowed media type") const {
    for (std::string& value : values) {
      value = validation_detail::trimLower(value);
      const std::size_t slash = value.find('/');
      if (slash == std::string::npos || slash == 0 || slash + 1 >= value.size() ||
          value.find('/', slash + 1) != std::string::npos ||
          (value.substr(0, slash).find('*') != std::string::npos && value.substr(0, slash) != "*") ||
          (value.substr(slash + 1).find('*') != std::string::npos && value.substr(slash + 1) != "*") ||
          (value.substr(0, slash) == "*" && value.substr(slash + 1) != "*"))
        throw std::invalid_argument("allowed MIME types must use type/subtype syntax");
    }
    return add(ValidationRuleKind::allowedMimeTypes, std::move(message), [values](const T& files) {
      for (const auto& file : files)
        if (!validation_detail::mimeAllowed(file.mimeType, values)) return false;
      return true;
    });
  }
  ValidationRules allowedExtensions(std::vector<std::string> values,
                                     std::string message = "A file has a disallowed extension") const {
    for (std::string& value : values) {
      value = validation_detail::trimLower(value);
      if (!value.empty() && value[0] == '.') value.erase(0, 1);
      if (value.empty()) throw std::invalid_argument("allowed extensions cannot contain an empty value");
    }
    return add(ValidationRuleKind::allowedExtensions, std::move(message), [values](const T& files) {
      for (const auto& file : files)
        if (std::find(values.begin(), values.end(), validation_detail::extensionOf(file.name)) == values.end())
          return false;
      return true;
    });
  }
  ValidationRules maxFiles(int count, std::string message = "Too many files are selected") const {
    requireNonNegative(count, "maximum file count");
    return add(ValidationRuleKind::maxFiles, std::move(message),
        [count](const T& files) { return static_cast<int>(files.size()) <= count; });
  }
  ValidationRules custom(std::function<bool(const T&)> validator,
                          std::string message = "Value is invalid") const {
    if (!validator) throw std::invalid_argument("custom validation procedure is required");
    return add(ValidationRuleKind::custom, std::move(message), std::move(validator));
  }

  ValidationResult validate(const T& value) const {
    const bool absent = validation_detail::Traits<T>::absent(value);
    bool optionalValue = false;
    int requiredIndex = -1;
    for (std::size_t index = 0; index < rules_.size(); ++index) {
      if (rules_[index].kind == ValidationRuleKind::optional) optionalValue = true;
      if (rules_[index].kind == ValidationRuleKind::required) requiredIndex = static_cast<int>(index);
    }
    if (absent && requiredIndex >= 0) {
      const Rule& rule = rules_[static_cast<std::size_t>(requiredIndex)];
      return ValidationResult::invalid(rule.kind, rule.message, requiredIndex);
    }
    if (absent && optionalValue) return ValidationResult::valid();
    for (std::size_t index = 0; index < rules_.size(); ++index) {
      const Rule& rule = rules_[index];
      if (rule.kind == ValidationRuleKind::required || rule.kind == ValidationRuleKind::optional)
        continue;
      if (!rule.test(value))
        return ValidationResult::invalid(rule.kind, rule.message, static_cast<int>(index));
    }
    return ValidationResult::valid();
  }

  std::vector<ValidationValue<T>> dependencyReferences() const {
    std::vector<ValidationValue<T>> result;
    for (const Rule& rule : rules_) {
      if (!rule.peer) continue;
      const bool duplicate = std::any_of(
          result.begin(), result.end(), [&](const ValidationValue<T>& value) {
            return value.value_ == rule.peer;
          });
      if (!duplicate) result.push_back(ValidationValue<T>(rule.peer));
    }
    return result;
  }

 private:
  ValidationRules add(ValidationRuleKind kind, std::string message,
                      std::function<bool(const T&)> test) const {
    ValidationRules result = *this;
    result.rules_.push_back({kind, std::move(message), std::move(test), nullptr});
    return result;
  }
  static void requireNonNegative(int value, const char* name) {
    if (value < 0) throw std::invalid_argument(std::string(name) + " cannot be negative");
  }
  template <typename U = T>
  static typename std::enable_if<std::is_arithmetic<U>::value>::type
  requireOrderedLimit(U value) {
    if (std::isnan(static_cast<double>(value)))
      throw std::invalid_argument("numeric validation limit cannot be NaN");
  }
  template <typename U = T>
  static typename std::enable_if<std::is_arithmetic<U>::value>::type
  requireFiniteDivisor(U value) {
    if (!std::isfinite(static_cast<double>(value)))
      throw std::invalid_argument("multipleOf divisor must be finite");
  }

  std::vector<Rule> rules_;
};

template <typename T>
class ValidationBinding {
 public:
  ValidationBinding(ValidationRules<T> rules, T value,
                    ValidationReport reportOn = ValidationReport::onBlur)
      : rules_(std::move(rules)), value_(std::move(value)), reportOn_(reportOn),
        result_(rules_.validate(value_.get())) {}

  ValidationResult evaluate(T value,
                            ValidationTrigger trigger = ValidationTrigger::explicitCheck,
                            bool forceReport = false) {
    value_.set(std::move(value));
    result_ = rules_.validate(value_.get());
    if (forceReport ||
        (trigger == ValidationTrigger::input && reportOn_ == ValidationReport::onInput) ||
        (trigger == ValidationTrigger::blur && reportOn_ != ValidationReport::onSubmit) ||
        (trigger == ValidationTrigger::submit && reportOn_ == ValidationReport::onSubmit))
      hasReported_ = true;
    return result_;
  }

  bool shouldExpose() const { return hasReported_ && !result_.isValid; }
  std::string validationMessage() const {
    return shouldExpose() ? result_.issue.message : std::string();
  }
  const ValidationResult& current() const { return result_; }
  ValidationValue<T> valueReference() const { return value_; }
  bool hasReported() const { return hasReported_; }

 private:
  ValidationRules<T> rules_;
  ValidationValue<T> value_;
  ValidationReport reportOn_;
  ValidationResult result_;
  bool hasReported_ = false;
};

}  // namespace cbss

#endif
