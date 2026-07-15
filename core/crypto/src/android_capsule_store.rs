use std::sync::OnceLock;

use jni::{
    objects::{JByteArray, JClass, JObject, JValue},
    JNIEnv, JavaVM,
};

use crate::{KeyStoreError, LocalKeyCapsuleSlot};

const STORE_CLASS: &str = "dev/todori/todori/AndroidCapsuleStore";
static JAVA_VM: OnceLock<JavaVM> = OnceLock::new();

/// Installs the Flutter process Java VM before Dart initializes the Rust core.
/// No secret crosses this boundary; capsule bytes move only during explicit
/// Keystore seal/unseal calls below.
#[no_mangle]
pub extern "system" fn Java_dev_todori_todori_AndroidCapsuleStore_nativeInstallContext(
    env: JNIEnv<'_>,
    _class: JClass<'_>,
) {
    if let Ok(vm) = env.get_java_vm() {
        let _ = JAVA_VM.set(vm);
    }
}

pub(crate) fn load(
    namespace: &str,
    slot: LocalKeyCapsuleSlot,
) -> Result<Option<Vec<u8>>, KeyStoreError> {
    load_named(namespace, slot.label())
}

pub(crate) fn load_named(namespace: &str, slot: &str) -> Result<Option<Vec<u8>>, KeyStoreError> {
    with_env(|env| {
        let namespace = env.new_string(namespace).map_err(jni_error)?;
        let namespace_object = JObject::from(namespace);
        let slot = env.new_string(slot).map_err(jni_error)?;
        let slot_object = JObject::from(slot);
        let value = env
            .call_static_method(
                STORE_CLASS,
                "load",
                "(Ljava/lang/String;Ljava/lang/String;)[B",
                &[
                    JValue::Object(&namespace_object),
                    JValue::Object(&slot_object),
                ],
            )
            .map_err(jni_error)?
            .l()
            .map_err(jni_error)?;
        if value.is_null() {
            return Ok(None);
        }
        let array = JByteArray::from(value);
        let plaintext = env.convert_byte_array(&array).map_err(jni_error)?;
        let zeros = vec![0_i8; plaintext.len()];
        env.set_byte_array_region(&array, 0, &zeros)
            .map_err(jni_error)?;
        Ok(Some(plaintext))
    })
}

pub(crate) fn store(
    namespace: &str,
    slot: LocalKeyCapsuleSlot,
    value: &[u8],
) -> Result<(), KeyStoreError> {
    store_named(namespace, slot.label(), value)
}

pub(crate) fn store_named(namespace: &str, slot: &str, value: &[u8]) -> Result<(), KeyStoreError> {
    with_env(|env| {
        let namespace = env.new_string(namespace).map_err(jni_error)?;
        let namespace_object = JObject::from(namespace);
        let slot = env.new_string(slot).map_err(jni_error)?;
        let slot_object = JObject::from(slot);
        let bytes = env.byte_array_from_slice(value).map_err(jni_error)?;
        env.call_static_method(
            STORE_CLASS,
            "store",
            "(Ljava/lang/String;Ljava/lang/String;[B)V",
            &[
                JValue::Object(&namespace_object),
                JValue::Object(&slot_object),
                JValue::Object(bytes.as_ref()),
            ],
        )
        .map_err(jni_error)?;
        let zeros = vec![0_i8; value.len()];
        env.set_byte_array_region(&bytes, 0, &zeros)
            .map_err(jni_error)?;
        Ok(())
    })
}

pub(crate) fn delete(namespace: &str, slot: LocalKeyCapsuleSlot) -> Result<(), KeyStoreError> {
    delete_named(namespace, slot.label())
}

pub(crate) fn delete_named(namespace: &str, slot: &str) -> Result<(), KeyStoreError> {
    with_env(|env| {
        let namespace = env.new_string(namespace).map_err(jni_error)?;
        let namespace_object = JObject::from(namespace);
        let slot = env.new_string(slot).map_err(jni_error)?;
        let slot_object = JObject::from(slot);
        env.call_static_method(
            STORE_CLASS,
            "delete",
            "(Ljava/lang/String;Ljava/lang/String;)V",
            &[
                JValue::Object(&namespace_object),
                JValue::Object(&slot_object),
            ],
        )
        .map_err(jni_error)?;
        Ok(())
    })
}

fn with_env<T>(
    operation: impl FnOnce(&mut JNIEnv<'_>) -> Result<T, KeyStoreError>,
) -> Result<T, KeyStoreError> {
    let vm = JAVA_VM
        .get()
        .ok_or(KeyStoreError::PlatformStoreUnavailable)?;
    let mut env = vm.attach_current_thread().map_err(jni_error)?;
    operation(&mut env)
}

fn jni_error(_error: jni::errors::Error) -> KeyStoreError {
    // JNI exception messages can contain provider internals. Keep the public
    // error deliberately typed and secret-free.
    KeyStoreError::Backend("Android Keystore operation failed".to_string())
}
