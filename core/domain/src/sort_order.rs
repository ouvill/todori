//! Deterministic fractional sort-order generation.
//!
//! Values use only ASCII alphanumerics ordered as
//! `0-9A-Za-z`, so Rust `String`, Dart `String.compareTo`, and SQLite `TEXT`
//! binary ordering agree for generated values.

use crate::usecases::DomainError;

const ALPHABET: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const MIN_DIGIT: i32 = -1;
const MAX_DIGIT: i32 = ALPHABET.len() as i32;

/// Generates a sort order strictly between `previous` and `next`.
///
/// At least one valid value must exist between the two boundaries. Existing
/// boundaries must be non-empty, contain only [`ALPHABET`] characters, and be
/// ordered as `previous < next` when both are present.
pub fn fractional_index_between(
    previous: Option<&str>,
    next: Option<&str>,
) -> Result<String, DomainError> {
    if let Some(value) = previous {
        validate_sort_order(value)?;
    }
    if let Some(value) = next {
        validate_sort_order(value)?;
    }
    if let (Some(previous), Some(next)) = (previous, next) {
        if previous >= next {
            return Err(DomainError::InvalidSortOrderBoundary);
        }
    }

    let previous_bytes = previous.unwrap_or_default().as_bytes();
    let next_bytes = next.unwrap_or_default().as_bytes();
    let mut prefix = Vec::new();
    let mut index = 0;

    loop {
        let previous_digit = digit_at(previous_bytes, index, previous.is_some(), true)?;
        let next_digit = digit_at(next_bytes, index, next.is_some(), false)?;

        if next_digit - previous_digit > 1 {
            let digit = previous_digit + ((next_digit - previous_digit) / 2);
            prefix.push(ALPHABET[digit as usize]);
            return String::from_utf8(prefix).map_err(|_| DomainError::InvalidSortOrder);
        }

        if previous_digit < 0 {
            if next.is_some() && index + 1 < next_bytes.len() {
                prefix.push(ALPHABET[next_digit as usize]);
                return String::from_utf8(prefix).map_err(|_| DomainError::InvalidSortOrder);
            }
            return Err(DomainError::SortOrderSpaceExhausted);
        }

        prefix.push(ALPHABET[previous_digit as usize]);
        index += 1;
    }
}

/// Generates a sort order after the current last value.
pub fn fractional_index_after(last: Option<&str>) -> Result<String, DomainError> {
    fractional_index_between(last, None)
}

fn validate_sort_order(value: &str) -> Result<(), DomainError> {
    if value.is_empty() || !value.bytes().all(|byte| ALPHABET.contains(&byte)) {
        return Err(DomainError::InvalidSortOrder);
    }
    Ok(())
}

fn digit_at(
    bytes: &[u8],
    index: usize,
    has_boundary: bool,
    is_previous: bool,
) -> Result<i32, DomainError> {
    match bytes.get(index) {
        Some(byte) => ALPHABET
            .iter()
            .position(|candidate| candidate == byte)
            .map(|position| position as i32)
            .ok_or(DomainError::InvalidSortOrder),
        None if !has_boundary => Ok(if is_previous { MIN_DIGIT } else { MAX_DIGIT }),
        None if is_previous => Ok(MIN_DIGIT),
        None => Ok(MAX_DIGIT),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_initial_value() {
        assert_eq!(fractional_index_between(None, None).unwrap(), "U");
    }

    #[test]
    fn generates_before_existing_value() {
        let generated = fractional_index_between(None, Some("a0")).unwrap();

        assert!(generated.as_str() < "a0");
    }

    #[test]
    fn generates_before_prefixed_low_value() {
        let generated = fractional_index_between(None, Some("0U")).unwrap();

        assert_eq!(generated, "0");
        assert!(generated.as_str() < "0U");
    }

    #[test]
    fn generates_after_existing_value() {
        let generated = fractional_index_after(Some("a0")).unwrap();

        assert!("a0" < generated.as_str());
    }

    #[test]
    fn generates_between_two_values() {
        let generated = fractional_index_between(Some("a0"), Some("a1")).unwrap();

        assert!("a0" < generated.as_str());
        assert!(generated.as_str() < "a1");
    }

    #[test]
    fn supports_repeated_insertions_between_values() {
        let upper = "a1".to_string();
        let mut lower = "a0".to_string();

        for _ in 0..16 {
            let generated = fractional_index_between(Some(&lower), Some(&upper)).unwrap();
            assert!(lower < generated);
            assert!(generated < upper);
            lower = generated;
        }
    }

    #[test]
    fn rejects_invalid_values() {
        assert_eq!(
            fractional_index_between(Some(""), None),
            Err(DomainError::InvalidSortOrder)
        );
        assert_eq!(
            fractional_index_between(Some("a_0"), None),
            Err(DomainError::InvalidSortOrder)
        );
    }

    #[test]
    fn rejects_invalid_boundaries() {
        assert_eq!(
            fractional_index_between(Some("a1"), Some("a0")),
            Err(DomainError::InvalidSortOrderBoundary)
        );
        assert_eq!(
            fractional_index_between(Some("a0"), Some("a0")),
            Err(DomainError::InvalidSortOrderBoundary)
        );
    }
}
