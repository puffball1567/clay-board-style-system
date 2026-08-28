use std::ffi::CString;
use std::ptr::NonNull;

use crate::{
    c_string, ffi, CapabilityRequirement, Contract, Error, Result, CAPABILITY_BLOB,
    CAPABILITY_FORM_DATA, STATUS_INTERNAL_ERROR, STATUS_INVALID_HANDLE, STATUS_OK,
    STATUS_OUT_OF_RANGE,
};

const FORM_DATA_TEXT: u32 = 0;
const FORM_DATA_BLOB: u32 = 1;
const MAX_FORM_DATA_NAME_BYTES: usize = 65_536;
const MAX_FORM_DATA_TEXT_BYTES: usize = 16 * 1024 * 1024;

pub struct Blob {
    handle: NonNull<ffi::CbssBlob>,
}

impl Blob {
    pub fn new(bytes: &[u8], mime_type: &str) -> Result<Self> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_BLOB,
            minimum_version: 1,
        }])?;
        let mime_type = c_string(mime_type, "Blob MIME type")?;
        let mut output = std::ptr::null_mut();
        let status = unsafe {
            ffi::cbss_blob_create(
                if bytes.is_empty() {
                    std::ptr::null()
                } else {
                    bytes.as_ptr()
                },
                bytes.len() as u64,
                mime_type.as_ptr(),
                &mut output,
            )
        };
        if status != STATUS_OK {
            return Err(Error::status(status, "create Blob"));
        }
        Self::from_owned(output, "create Blob")
    }

    pub fn size(&self) -> u64 {
        unsafe { ffi::cbss_blob_size(self.handle.as_ptr()) }
    }

    pub fn mime_type(&self) -> Result<String> {
        read_string(
            |buffer, capacity| unsafe {
                ffi::cbss_blob_mime_type(self.handle.as_ptr(), buffer, capacity)
            },
            MAX_FORM_DATA_NAME_BYTES,
            "read Blob MIME type",
        )
    }

    pub fn read(&self, offset: u64, capacity: u32) -> Result<Vec<u8>> {
        let mut bytes = vec![0_u8; capacity as usize];
        let mut read = 0_u32;
        let status = unsafe {
            ffi::cbss_blob_read(
                self.handle.as_ptr(),
                offset,
                if bytes.is_empty() {
                    std::ptr::null_mut()
                } else {
                    bytes.as_mut_ptr()
                },
                capacity,
                &mut read,
            )
        };
        if status != STATUS_OK {
            return Err(Error::status(status, "read Blob"));
        }
        bytes.truncate(read as usize);
        Ok(bytes)
    }

    pub(crate) fn as_ptr(&self) -> *mut ffi::CbssBlob {
        self.handle.as_ptr()
    }

    pub(crate) fn from_owned(raw: *mut ffi::CbssBlob, operation: &str) -> Result<Self> {
        NonNull::new(raw)
            .map(|handle| Self { handle })
            .ok_or_else(|| Error::status(STATUS_INVALID_HANDLE, operation))
    }
}

impl Clone for Blob {
    fn clone(&self) -> Self {
        let status = unsafe { ffi::cbss_blob_retain(self.handle.as_ptr()) };
        assert_eq!(status, STATUS_OK, "retain Blob failed with status {status}");
        Self {
            handle: self.handle,
        }
    }
}

impl Drop for Blob {
    fn drop(&mut self) {
        unsafe { ffi::cbss_blob_release(self.handle.as_ptr()) };
    }
}

pub enum FormDataValue {
    Text(String),
    Blob {
        blob: Blob,
        file_name: Option<String>,
    },
}

pub struct FormDataEntry {
    pub name: String,
    pub value: FormDataValue,
}

pub struct FormData {
    handle: NonNull<ffi::CbssFormData>,
}

impl FormData {
    pub fn len(&self) -> usize {
        unsafe { ffi::cbss_form_data_length(self.handle.as_ptr()) as usize }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub fn entry(&self, index: usize) -> Result<FormDataEntry> {
        let index = u32::try_from(index)
            .map_err(|_| Error::status(STATUS_OUT_OF_RANGE, "read FormData entry"))?;
        let mut kind = u32::MAX;
        let status =
            unsafe { ffi::cbss_form_data_entry_kind(self.handle.as_ptr(), index, &mut kind) };
        if status != STATUS_OK {
            return Err(Error::status(status, "read FormData entry kind"));
        }
        let name = read_string(
            |buffer, capacity| unsafe {
                ffi::cbss_form_data_entry_name(self.handle.as_ptr(), index, buffer, capacity)
            },
            MAX_FORM_DATA_NAME_BYTES,
            "read FormData entry name",
        )?;
        let value = match kind {
            FORM_DATA_TEXT => FormDataValue::Text(read_string(
                |buffer, capacity| unsafe {
                    ffi::cbss_form_data_entry_text(self.handle.as_ptr(), index, buffer, capacity)
                },
                MAX_FORM_DATA_TEXT_BYTES,
                "read FormData text value",
            )?),
            FORM_DATA_BLOB => {
                let mut raw = std::ptr::null_mut();
                let status = unsafe {
                    ffi::cbss_form_data_entry_blob(self.handle.as_ptr(), index, &mut raw)
                };
                if status != STATUS_OK {
                    return Err(Error::status(status, "read FormData Blob value"));
                }
                let blob = Blob::from_owned(raw, "read FormData Blob value")?;
                let file_name = read_string(
                    |buffer, capacity| unsafe {
                        ffi::cbss_form_data_entry_file_name(
                            self.handle.as_ptr(),
                            index,
                            buffer,
                            capacity,
                        )
                    },
                    MAX_FORM_DATA_NAME_BYTES,
                    "read FormData file name",
                )?;
                FormDataValue::Blob {
                    blob,
                    file_name: (!file_name.is_empty()).then_some(file_name),
                }
            }
            _ => {
                return Err(Error::status(
                    STATUS_INTERNAL_ERROR,
                    "read FormData entry: runtime returned an unknown value kind",
                ))
            }
        };
        Ok(FormDataEntry { name, value })
    }

    pub fn entries(&self) -> Result<Vec<FormDataEntry>> {
        (0..self.len()).map(|index| self.entry(index)).collect()
    }

    pub fn values(&self, name: &str) -> Result<Vec<FormDataEntry>> {
        let mut result = Vec::new();
        for index in 0..self.len() {
            let entry = self.entry(index)?;
            if entry.name == name {
                result.push(entry);
            }
        }
        Ok(result)
    }

    pub(crate) fn as_ptr(&self) -> *mut ffi::CbssFormData {
        self.handle.as_ptr()
    }

    pub(crate) fn from_owned(raw: *mut ffi::CbssFormData, operation: &str) -> Result<Self> {
        NonNull::new(raw)
            .map(|handle| Self { handle })
            .ok_or_else(|| Error::status(STATUS_INVALID_HANDLE, operation))
    }
}

impl Clone for FormData {
    fn clone(&self) -> Self {
        let status = unsafe { ffi::cbss_form_data_retain(self.handle.as_ptr()) };
        assert_eq!(
            status, STATUS_OK,
            "retain FormData failed with status {status}"
        );
        Self {
            handle: self.handle,
        }
    }
}

impl Drop for FormData {
    fn drop(&mut self) {
        unsafe { ffi::cbss_form_data_release(self.handle.as_ptr()) };
    }
}

pub struct FormDataBuilder {
    handle: Option<NonNull<ffi::CbssFormDataBuilder>>,
}

impl FormDataBuilder {
    pub fn new() -> Result<Self> {
        Contract::require(&[CapabilityRequirement {
            id: CAPABILITY_FORM_DATA,
            minimum_version: 1,
        }])?;
        let handle = NonNull::new(unsafe { ffi::cbss_form_data_builder_create() })
            .ok_or_else(|| Error::status(STATUS_INVALID_HANDLE, "create FormData builder"))?;
        Ok(Self {
            handle: Some(handle),
        })
    }

    pub fn add_text(&mut self, name: &str, value: &str) -> Result<&mut Self> {
        let name = c_string(name, "FormData field name")?;
        let value = c_string(value, "FormData text value")?;
        let status = unsafe {
            ffi::cbss_form_data_builder_add_text(
                self.require_handle()?.as_ptr(),
                name.as_ptr(),
                value.as_ptr(),
            )
        };
        if status != STATUS_OK {
            return Err(Error::status(status, "add FormData text value"));
        }
        Ok(self)
    }

    pub fn add_blob(
        &mut self,
        name: &str,
        blob: &Blob,
        file_name: Option<&str>,
    ) -> Result<&mut Self> {
        let name = c_string(name, "FormData field name")?;
        let file_name = file_name
            .map(|value| c_string(value, "FormData file name"))
            .transpose()?;
        let empty = CString::new("").expect("empty CString");
        let status = unsafe {
            ffi::cbss_form_data_builder_add_blob(
                self.require_handle()?.as_ptr(),
                name.as_ptr(),
                blob.as_ptr(),
                file_name.as_ref().unwrap_or(&empty).as_ptr(),
            )
        };
        if status != STATUS_OK {
            return Err(Error::status(status, "add FormData Blob value"));
        }
        Ok(self)
    }

    pub fn finish(mut self) -> Result<FormData> {
        let handle = self.require_handle()?;
        let mut output = std::ptr::null_mut();
        let status = unsafe { ffi::cbss_form_data_builder_finish(handle.as_ptr(), &mut output) };
        if status != STATUS_OK {
            return Err(Error::status(status, "finish FormData builder"));
        }
        unsafe { ffi::cbss_form_data_builder_destroy(handle.as_ptr()) };
        self.handle = None;
        FormData::from_owned(output, "finish FormData builder")
    }

    fn require_handle(&self) -> Result<NonNull<ffi::CbssFormDataBuilder>> {
        self.handle
            .ok_or_else(|| Error::status(STATUS_INVALID_HANDLE, "FormData builder is finished"))
    }
}

impl Drop for FormDataBuilder {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            unsafe { ffi::cbss_form_data_builder_destroy(handle.as_ptr()) };
        }
    }
}

fn read_string<F>(mut reader: F, maximum: usize, operation: &str) -> Result<String>
where
    F: FnMut(*mut std::os::raw::c_char, u32) -> u32,
{
    let length = reader(std::ptr::null_mut(), 0) as usize;
    if length > maximum || length > u32::MAX as usize - 1 {
        return Err(Error::status(STATUS_OUT_OF_RANGE, operation));
    }
    if length == 0 {
        return Ok(String::new());
    }
    let mut bytes = vec![0_u8; length + 1];
    let written = reader(bytes.as_mut_ptr().cast(), bytes.len() as u32) as usize;
    if written != length {
        return Err(Error::status(STATUS_INTERNAL_ERROR, operation));
    }
    String::from_utf8(bytes[..length].to_vec())
        .map_err(|_| Error::status(STATUS_INTERNAL_ERROR, operation))
}
