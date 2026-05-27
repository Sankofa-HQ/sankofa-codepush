// Wrappers around crate::log's logging functions that prepend "[sankofa]" to the log message.
//
// See https://stackoverflow.com/questions/67087597/is-it-possible-to-use-rusts-log-info-for-tests
// for the rationale behind the use of the #[cfg(test)] attribute.

#[cfg(test)]
#[macro_export]
macro_rules! sankofa_info {
    ($fmt:expr $(, $($arg:tt)*)?) => {
        println!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(not(test))]
#[macro_export]
macro_rules! sankofa_info {
    // sankofa_info!("a {} event", "log")
    ($fmt:expr $(, $($arg:tt)*)?) => {
        log::info!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(test)]
#[macro_export]
macro_rules! sankofa_debug {
    ($fmt:expr $(, $($arg:tt)*)?) => {
        println!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(not(test))]
#[macro_export]
macro_rules! sankofa_debug {
    // sankofa_debug!("a {} event", "log")
    ($fmt:expr $(, $($arg:tt)*)?) => {
        log::debug!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(test)]
#[macro_export]
macro_rules! sankofa_warn {
    ($fmt:expr $(, $($arg:tt)*)?) => {
        println!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(not(test))]
#[macro_export]
macro_rules! sankofa_warn {
    // sankofa_warn!("a {} event", "log")
    ($fmt:expr $(, $($arg:tt)*)?) => {
        log::warn!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(test)]
#[macro_export]
macro_rules! sankofa_error {
    ($fmt:expr $(, $($arg:tt)*)?) => {
        println!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}

#[cfg(not(test))]
#[macro_export]
macro_rules! sankofa_error {
    // sankofa_error!("a {} event", "log")
    ($fmt:expr $(, $($arg:tt)*)?) => {
        log::error!(concat!("[sankofa] ", $fmt), $($($arg)*)?)
    };
}
