use std::sync::OnceLock;

use jni::{
    objects::{GlobalRef, JByteArray, JClass, JObject, JValue},
    JNIEnv, JavaVM,
};

use crate::{KeyStoreError, LocalKeyCapsuleSlot};

struct AndroidJniBridge {
    vm: JavaVM,
    // Rust workers attach as native threads, where FindClass cannot use the
    // application ClassLoader. Retain the app-loaded class passed by Kotlin.
    store_class: GlobalRef,
}

static ANDROID_JNI: OnceLock<AndroidJniBridge> = OnceLock::new();

/// Installs the Flutter process Java VM and application-loaded store class
/// before Dart initializes the Rust core.
/// No secret crosses this boundary; capsule bytes move only during explicit
/// Keystore seal/unseal calls below.
#[no_mangle]
pub extern "system" fn Java_com_taskveil_app_AndroidCapsuleStore_nativeInstallContext(
    env: JNIEnv<'_>,
    class: JClass<'_>,
) {
    if let (Ok(vm), Ok(store_class)) = (env.get_java_vm(), env.new_global_ref(&class)) {
        let _ = ANDROID_JNI.set(AndroidJniBridge { vm, store_class });
    }
}

pub(crate) fn load(
    namespace: &str,
    slot: LocalKeyCapsuleSlot,
) -> Result<Option<Vec<u8>>, KeyStoreError> {
    load_named(namespace, slot.label())
}

pub(crate) fn load_named(namespace: &str, slot: &str) -> Result<Option<Vec<u8>>, KeyStoreError> {
    with_env(|env, store_class| {
        let namespace = env.new_string(namespace).map_err(jni_error)?;
        let namespace_object = JObject::from(namespace);
        let slot = env.new_string(slot).map_err(jni_error)?;
        let slot_object = JObject::from(slot);
        let value = env
            .call_static_method(
                store_class,
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
    with_env(|env, store_class| {
        let namespace = env.new_string(namespace).map_err(jni_error)?;
        let namespace_object = JObject::from(namespace);
        let slot = env.new_string(slot).map_err(jni_error)?;
        let slot_object = JObject::from(slot);
        let bytes = env.byte_array_from_slice(value).map_err(jni_error)?;
        env.call_static_method(
            store_class,
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
    with_env(|env, store_class| {
        let namespace = env.new_string(namespace).map_err(jni_error)?;
        let namespace_object = JObject::from(namespace);
        let slot = env.new_string(slot).map_err(jni_error)?;
        let slot_object = JObject::from(slot);
        env.call_static_method(
            store_class,
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
    operation: impl FnOnce(&mut JNIEnv<'_>, &GlobalRef) -> Result<T, KeyStoreError>,
) -> Result<T, KeyStoreError> {
    let bridge = ANDROID_JNI
        .get()
        .ok_or(KeyStoreError::PlatformStoreUnavailable)?;
    let mut env = bridge.vm.attach_current_thread().map_err(jni_error)?;
    operation(&mut env, &bridge.store_class)
}

fn jni_error(_error: jni::errors::Error) -> KeyStoreError {
    // JNI exception messages can contain provider internals. Keep the public
    // error deliberately typed and secret-free.
    KeyStoreError::Backend("Android Keystore operation failed".to_string())
}
