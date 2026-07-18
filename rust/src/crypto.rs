use aes::cipher::{block_padding::Pkcs7, BlockEncryptMut, KeyInit, KeyIvInit};
use aes::Aes128;
use base64::{engine::general_purpose::STANDARD, Engine};
use md5::{Digest, Md5};
use num_bigint::BigUint;
use rand::{distributions::Alphanumeric, rngs::OsRng, Rng};
use serde_json::Value;
use std::collections::BTreeMap;

const WEAPI_KEY: &[u8; 16] = b"0CoJUm6Qyw8W8jud";
const WEAPI_IV: &[u8; 16] = b"0102030405060708";
const EAPI_KEY: &[u8; 16] = b"e82ckenh8dichen8";
const RSA_MODULUS: &str = "e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7";

pub(crate) fn md5_hex(input: &str) -> String {
    hex::encode(Md5::digest(input.as_bytes()))
}

pub(crate) fn weapi_encrypt(payload: &Value) -> Result<BTreeMap<String, String>, String> {
    let json = serde_json::to_string(payload)
        .map_err(|error| format!("序列化 WEAPI 参数失败：{error}"))?;
    let secret: String = OsRng
        .sample_iter(&Alphanumeric)
        .take(16)
        .map(char::from)
        .collect();
    let first = aes_cbc_base64(json.as_bytes(), WEAPI_KEY, WEAPI_IV)?;
    let second = aes_cbc_base64(first.as_bytes(), secret.as_bytes(), WEAPI_IV)?;
    let reversed: String = secret.chars().rev().collect();
    let modulus = BigUint::parse_bytes(RSA_MODULUS.as_bytes(), 16)
        .ok_or_else(|| "RSA 公钥无效".to_string())?;
    let encrypted = BigUint::from_bytes_be(reversed.as_bytes())
        .modpow(&BigUint::from(65_537u32), &modulus)
        .to_str_radix(16);

    Ok(BTreeMap::from([
        ("params".into(), second),
        ("encSecKey".into(), format!("{encrypted:0>256}")),
    ]))
}

pub(crate) fn eapi_encrypt(path: &str, payload: &Value) -> Result<String, String> {
    let api_path = path.replacen("/eapi", "/api", 1);
    let json =
        serde_json::to_string(payload).map_err(|error| format!("序列化 EAPI 参数失败：{error}"))?;
    let digest = md5_hex(&format!("nobody{api_path}use{json}md5forencrypt"));
    let message = format!("{api_path}-36cd479b6b5-{json}-36cd479b6b5-{digest}");
    let mut buffer = padded_buffer(message.as_bytes());
    let length = message.len();
    let encrypted = ecb::Encryptor::<Aes128>::new_from_slice(EAPI_KEY)
        .map_err(|_| "EAPI AES 密钥无效".to_string())?
        .encrypt_padded_mut::<Pkcs7>(&mut buffer, length)
        .map_err(|_| "EAPI AES 加密失败".to_string())?;
    Ok(hex::encode_upper(encrypted))
}

fn aes_cbc_base64(input: &[u8], key: &[u8], iv: &[u8]) -> Result<String, String> {
    let mut buffer = padded_buffer(input);
    let encrypted = cbc::Encryptor::<Aes128>::new_from_slices(key, iv)
        .map_err(|_| "WEAPI AES 密钥或 IV 无效".to_string())?
        .encrypt_padded_mut::<Pkcs7>(&mut buffer, input.len())
        .map_err(|_| "WEAPI AES 加密失败".to_string())?;
    Ok(STANDARD.encode(encrypted))
}

fn padded_buffer(input: &[u8]) -> Vec<u8> {
    let mut buffer = Vec::with_capacity(input.len() + 16);
    buffer.extend_from_slice(input);
    buffer.resize(input.len() + 16, 0);
    buffer
}
