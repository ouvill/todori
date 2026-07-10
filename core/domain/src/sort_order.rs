//! Fixed-width 128-bit rank generation.

use crate::usecases::DomainError;

pub const MIN_RANK: &str = "00000000000000000000000000000000";
pub const MAX_RANK: &str = "ffffffffffffffffffffffffffffffff";

pub fn fractional_index_between(
    previous: Option<&str>,
    next: Option<&str>,
) -> Result<String, DomainError> {
    let lower = previous.map(parse_rank).transpose()?.unwrap_or(0);
    let upper = next.map(parse_rank).transpose()?.unwrap_or(u128::MAX);
    if previous.is_some() && next.is_some() && lower >= upper {
        return Err(DomainError::InvalidSortOrderBoundary);
    }
    if upper.saturating_sub(lower) <= 1 {
        return Err(DomainError::SortOrderSpaceExhausted);
    }
    Ok(format_rank(lower + (upper - lower) / 2))
}

pub fn fractional_index_after(last: Option<&str>) -> Result<String, DomainError> {
    fractional_index_between(last, None)
}

pub fn rebalance_ranks(count: usize) -> Result<Vec<String>, DomainError> {
    if count == 0 {
        return Ok(Vec::new());
    }
    let divisor = u128::try_from(count)
        .map_err(|_| DomainError::SortOrderSpaceExhausted)?
        .checked_add(1)
        .ok_or(DomainError::SortOrderSpaceExhausted)?;
    let step = u128::MAX / divisor;
    if step == 0 {
        return Err(DomainError::SortOrderSpaceExhausted);
    }
    Ok((1..=count)
        .map(|index| format_rank(step * index as u128))
        .collect())
}

pub fn validate_sort_order(value: &str) -> Result<(), DomainError> {
    parse_rank(value).map(|_| ())
}

fn parse_rank(value: &str) -> Result<u128, DomainError> {
    if value.len() != 32
        || !value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(DomainError::InvalidSortOrder);
    }
    u128::from_str_radix(value, 16).map_err(|_| DomainError::InvalidSortOrder)
}

fn format_rank(value: u128) -> String {
    format!("{value:032x}")
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fixed_width_midpoints_sort_lexically_like_u128() {
        let initial = fractional_index_between(None, None).unwrap();
        assert_eq!(initial, "7fffffffffffffffffffffffffffffff");
        let after = fractional_index_after(Some(&initial)).unwrap();
        assert_eq!(after.len(), 32);
        assert!(initial < after);
        let before = fractional_index_between(None, Some(&initial)).unwrap();
        assert!(before < initial);
    }
    #[test]
    fn adjacent_space_exhaustion_and_strict_codec() {
        assert_eq!(
            fractional_index_between(Some(MIN_RANK), Some("00000000000000000000000000000001")),
            Err(DomainError::SortOrderSpaceExhausted)
        );
        assert_eq!(
            validate_sort_order("A0000000000000000000000000000000"),
            Err(DomainError::InvalidSortOrder)
        );
        assert_eq!(
            validate_sort_order("a0"),
            Err(DomainError::InvalidSortOrder)
        );
    }
    #[test]
    fn rebalance_is_even_and_stable() {
        let ranks = rebalance_ranks(3).unwrap();
        assert_eq!(ranks.len(), 3);
        assert!(ranks[0] < ranks[1] && ranks[1] < ranks[2]);
        assert!(MIN_RANK < ranks[0].as_str());
        assert!(ranks[2].as_str() < MAX_RANK);
    }
}
