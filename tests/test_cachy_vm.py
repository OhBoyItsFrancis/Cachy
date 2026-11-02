"""Unit tests for bin/cachy-vm (no libvirt needed).  Run: python3 -m unittest tests/test_cachy_vm.py"""
import importlib.machinery
import importlib.util
import os
import tempfile
import unittest
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
loader = importlib.machinery.SourceFileLoader("cachy_vm", os.path.join(HERE, "..", "bin", "cachy-vm"))
spec = importlib.util.spec_from_loader("cachy_vm", loader)
vm = importlib.util.module_from_spec(spec)
loader.exec_module(vm)

# Ryzen 7 7700X: 8 cores, SMT siblings are N and N+8
CORES_7700X = [(i, i + 8) for i in range(8)]


def fake_sysfs(tmp, cores):
    for core in cores:
        for cpu in core:
            d = os.path.join(tmp, f"cpu{cpu}", "topology")
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "thread_siblings_list"), "w") as f:
                f.write(",".join(map(str, core)) + "\n")


class Pinning(unittest.TestCase):
    def test_sysfs_parse(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake_sysfs(tmp, CORES_7700X)
            self.assertEqual(vm.cpu_cores(tmp), CORES_7700X)

    def test_cpulist(self):
        self.assertEqual(vm.parse_cpulist("0-2,8"), [0, 1, 2, 8])

    def test_plan_keeps_host_core(self):
        pins, threads = vm.plan_pinning(CORES_7700X, [0, 8], 7)
        self.assertEqual(threads, 2)
        self.assertEqual(len(pins), 14)
        used = {c for _, c in pins}
        self.assertNotIn(0, used)
        self.assertNotIn(8, used)
        # vCPU pairs land on SMT siblings, matching the guest topology threads=2
        self.assertEqual(pins[0], (0, 1))
        self.assertEqual(pins[1], (1, 9))


class DomainXml(unittest.TestCase):
    def setUp(self):
        pins, threads = vm.plan_pinning(CORES_7700X, [0, 8], 7)
        self.xml = vm.domain_xml("win11", "16", "/var/lib/libvirt/images/win11.qcow2",
                                 "/var/lib/libvirt/images/Win11.iso",
                                 "/var/lib/libvirt/images/virtio-win.iso", pins, threads, [0, 8])
        self.root = ET.fromstring(self.xml)

    def test_win11_requirements(self):
        r = self.root
        self.assertEqual(r.find("os").get("firmware"), "efi")
        feats = {f.get("name"): f.get("enabled") for f in r.findall("os/firmware/feature")}
        self.assertEqual(feats, {"secure-boot": "yes", "enrolled-keys": "yes"})
        self.assertEqual(r.find("devices/tpm/backend").get("version"), "2.0")
        self.assertIsNotNone(r.find("features/smm"))
        topo = r.find("cpu/topology")
        self.assertEqual((topo.get("cores"), topo.get("threads")), ("7", "2"))
        self.assertEqual(r.find("vcpu").text, "14")
        self.assertEqual(r.find("cputune/emulatorpin").get("cpuset"), "0,8")

    def test_install_mode_has_spice_and_isos(self):
        d = self.root.find("devices")
        self.assertIsNotNone(d.find("graphics[@type='spice']"))
        self.assertEqual(len(d.findall("disk[@device='cdrom']")), 2)
        self.assertEqual(len(d.findall("hostdev")), 0)

    def test_passthrough_round_trip(self):
        gpu = ["0000:01:00.0", "0000:01:00.1"]
        usb = ["0000:0b:00.0"]
        vm.set_passthrough(self.root, True, gpu, usb, rom="/var/lib/libvirt/vbios/3080.rom")
        d = self.root.find("devices")
        hds = d.findall("hostdev")
        self.assertEqual(len(hds), 3)
        self.assertTrue(all(h.get("managed") == "yes" for h in hds))
        a = hds[0].find("source/address").attrib
        self.assertEqual((a["bus"], a["slot"], a["function"]), ("0x01", "0x00", "0x0"))
        self.assertEqual(hds[0].find("rom").get("file"), "/var/lib/libvirt/vbios/3080.rom")
        self.assertIsNone(hds[1].find("rom"))
        self.assertIsNone(d.find("graphics"))
        self.assertIsNone(d.find("sound"))
        self.assertEqual(d.find("video/model").get("type"), "none")
        # idempotent
        vm.set_passthrough(self.root, True, gpu, usb)
        self.assertEqual(len(d.findall("hostdev")), 3)
        self.assertEqual(len(d.findall("video")), 1)
        # and back
        vm.set_passthrough(self.root, False, gpu, usb)
        self.assertEqual(len(d.findall("hostdev")), 0)
        self.assertIsNotNone(d.find("graphics[@type='spice']"))
        self.assertEqual(d.find("video/model").get("type"), "virtio")
        ET.tostring(self.root)  # still serialisable

    def test_hook_matches_generated_hostdev(self):
        """The libvirt hook greps the domain XML for the GPU address; make sure
        ElementTree's serialisation matches that pattern."""
        import re
        vm.set_passthrough(self.root, True, ["0000:01:00.0"], [])
        s = ET.tostring(self.root, encoding="unicode")
        self.assertRegex(s, re.compile(r"<address domain=['\"]0x0000['\"] bus=['\"]0x01['\"] slot=['\"]0x00['\"]"))


class Conf(unittest.TestCase):
    def test_read_conf(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write('# c\nMODE=single\nVM_NAME="win11"\nHOST_CPUS="0,8"\nGPU_PCI=0000:01:00.0\n')
        c = vm.read_conf(f.name)
        os.unlink(f.name)
        self.assertEqual(c["MODE"], "single")
        self.assertEqual(c["VM_NAME"], "win11")
        self.assertEqual(c["HOST_CPUS"], "0,8")


if __name__ == "__main__":
    unittest.main()
