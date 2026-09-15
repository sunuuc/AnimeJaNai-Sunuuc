"""Offline regression tests for the standalone-runtime verifier (no Windows needed)."""
import struct
import unittest
from runtime_probe import pe_exports, classify_runtime, RUNTIME_EXPORTS, is_within


def fixture(names=('DotNetRuntimeInfo', 'g_CLREngineMetrics')):
    data = bytearray(4096)
    data[:2] = b'MZ'
    struct.pack_into('<I', data, 0x3c, 0x80)
    data[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HH', data, 0x84, 0x8664, 1)
    struct.pack_into('<H', data, 0x94, 0xf0)
    opt = 0x98
    struct.pack_into('<H', data, opt, 0x20b)
    struct.pack_into('<I', data, opt + 60, 0x200)
    struct.pack_into('<I', data, opt + 108, 16)
    struct.pack_into('<II', data, opt + 112, 0x1000, 0x400)
    section = opt + 0xf0
    data[section:section + 8] = b'.rdata\0\0'
    struct.pack_into('<IIII', data, section + 8, 0xe00, 0x1000, 0xe00, 0x200)
    struct.pack_into('<IIIII', data, 0x200 + 20, len(names), len(names), 0x1180, 0x11a0, 0x11c0)
    cursor = 0x400
    for i, name in enumerate(names):
        struct.pack_into('<I', data, 0x380 + 4*i, 0x1600 + i*8)
        struct.pack_into('<I', data, 0x3a0 + 4*i, cursor + 0xe00)
        struct.pack_into('<H', data, 0x3c0 + 2*i, i)
        value = name.encode('ascii') + b'\0'
        data[cursor:cursor + len(value)] = value
        cursor += len(value)
    return data


class PEChecks(unittest.TestCase):
    def test_real_static_marker_shape(self):
        self.assertTrue(RUNTIME_EXPORTS.issubset(pe_exports(fixture())))

    def test_framework_dependent_host_not_mistaken_for_static(self):
        self.assertEqual(pe_exports(fixture(('AnUnrelatedExport',))), {'AnUnrelatedExport'})

    def test_missing_export_table_is_not_static(self):
        data = fixture()
        struct.pack_into('<II', data, 0x98 + 112, 0, 0)
        self.assertEqual(pe_exports(data), set())

    def test_truncated_files_fail_closed(self):
        for length in (0, 1, 10, 60, 128, 151, 300, 800):
            with self.subTest(length=length), self.assertRaises(ValueError):
                pe_exports(fixture()[:length])

    def test_wrong_architecture(self):
        data = fixture()
        struct.pack_into('<H', data, 0x84, 0x14c)
        with self.assertRaises(ValueError): pe_exports(data)

    def test_bad_rva(self):
        data = fixture()
        struct.pack_into('<I', data, 0x3a0, 0xdeadbeef)
        with self.assertRaises(ValueError): pe_exports(data)

    def test_bad_ordinal(self):
        data = fixture()
        struct.pack_into('<H', data, 0x3c0, 99)
        with self.assertRaises(ValueError): pe_exports(data)

    def test_forwarder_does_not_prove_linked_clr(self):
        data = fixture()
        struct.pack_into('<I', data, 0x380, 0x1100)
        self.assertNotIn('DotNetRuntimeInfo', pe_exports(data))

    def test_exported_zero_initialized_data_is_valid(self):
        data = fixture()
        struct.pack_into('<I', data, 0x188 + 8, 0x2000)
        struct.pack_into('<I', data, 0x380, 0x2200)
        self.assertIn('DotNetRuntimeInfo', pe_exports(data))

    def test_target_outside_all_sections_is_rejected(self):
        data = fixture()
        struct.pack_into('<I', data, 0x380, 0x900000)
        with self.assertRaises(ValueError): pe_exports(data)

    def test_null_export_does_not_prove_linked_clr(self):
        data = fixture()
        struct.pack_into('<I', data, 0x380, 0)
        self.assertNotIn('DotNetRuntimeInfo', pe_exports(data))


class RuntimeChecks(unittest.TestCase):
    exe = r'C:\空目录\player\mpvnet.exe'
    root = r'C:\空目录\player'
    bundle = r'C:\test\bundles'

    def classify(self, modules, exports=()):
        return classify_runtime(self.exe, modules, exports, [self.root, self.bundle])

    def test_static_runtime_without_separate_coreclr(self):
        result = self.classify([self.exe, r'C:\Windows\System32\ntdll.dll'], RUNTIME_EXPORTS)
        self.assertEqual(result['runtime_mode'], 'statically-linked-singlefilehost')

    def test_bundled_dynamic_runtime(self):
        result = self.classify([self.exe, self.root + r'\coreclr.dll'])
        self.assertEqual(result['runtime_mode'], 'bundled-coreclr-dll')

    def test_extracted_dynamic_runtime(self):
        result = self.classify([self.exe, self.bundle + r'\mpvnet\hash\coreclr.dll'])
        self.assertEqual(result['runtime_mode'], 'bundled-coreclr-dll')

    def test_no_runtime_rejected(self):
        with self.assertRaises(RuntimeError): self.classify([self.exe])

    def test_global_runtime_rejected_even_with_static_markers(self):
        for root in (r'C:\Program Files\dotnet', r'D:\hostedtoolcache\dotnet', r'C:\other'):
            with self.subTest(root=root), self.assertRaises(RuntimeError):
                self.classify([self.exe, root + r'\coreclr.dll'], RUNTIME_EXPORTS)

    def test_external_host_library_rejected(self):
        with self.assertRaises(RuntimeError):
            self.classify([self.exe, r'C:\outside\hostfxr.dll'], RUNTIME_EXPORTS)

    def test_similarly_named_directory_is_not_allowed(self):
        with self.assertRaises(RuntimeError):
            self.classify([self.exe, self.root + r'-other\coreclr.dll'])

    def test_wrong_process_and_empty_list(self):
        for modules in ([], [r'C:\other\mpvnet.exe']):
            with self.subTest(modules=modules), self.assertRaises(RuntimeError):
                self.classify(modules, RUNTIME_EXPORTS)

    def test_windows_case_and_traversal(self):
        self.assertTrue(is_within(r'C:\TEST\bundles\app\coreclr.dll', self.bundle))
        self.assertFalse(is_within(self.bundle + r'\..\elsewhere\coreclr.dll', self.bundle))
        self.assertFalse(is_within(r'D:\test\bundles\coreclr.dll', self.bundle))


if __name__ == '__main__':
    unittest.main(verbosity=2)
