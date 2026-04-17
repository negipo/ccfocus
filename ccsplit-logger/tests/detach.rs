use ccsplit_logger::detach::{child_env_marker, is_detached_child};

#[test]
fn is_detached_child_false_when_env_absent() {
    unsafe {
        std::env::remove_var(child_env_marker());
    }
    assert!(!is_detached_child());
}

#[test]
fn is_detached_child_true_when_env_present() {
    unsafe {
        std::env::set_var(child_env_marker(), "1");
    }
    assert!(is_detached_child());
    unsafe {
        std::env::remove_var(child_env_marker());
    }
}
