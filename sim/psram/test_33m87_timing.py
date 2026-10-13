import unittest

from check_33m87_timing import check_report


REPORT = """
; Clocks ;
; Clock Name ; Type ; Period ; Frequency ;
; emu|psram_speed_pll|pll_inst|vcoph[0] ; Generated ; 2.460 ; 406.45 MHz ;
; emu|psram_speed_pll|pll_inst|counter|divclk ; Generated ; 14.762 ; 67.74 MHz ;
; PSRAM_33M87_CLK_EXT ; Generated ; 29.524 ; 33.87 MHz ;
; Setup Summary ;
; Clock ; Slack ; End Point TNS ;
; emu|psram_speed_pll|pll_inst|counter|divclk ; 0.353 ; 0.000 ;
; PSRAM_33M87_CLK_EXT ; 6.230 ; 0.000 ;
; Hold Summary ;
; Clock ; Slack ; End Point TNS ;
; emu|psram_speed_pll|pll_inst|counter|divclk ; 0.586 ; 0.000 ;
; PSRAM_33M87_CLK_EXT ; 2.716 ; 0.000 ;
; Recovery Summary ;
; FPGA_CLK1_50 ; 3.270 ; 0.000 ;
; Removal Summary ;
; FPGA_CLK1_50 ; 0.927 ; 0.000 ;
; Minimum Pulse Width Summary ;
; FPGA_CLK1_50 ; 1.091 ; 0.000 ;
; Unconstrained Output Ports ;
; PSRAM_CLK ; No output delay, min/max delays, false-path exceptions, or max skew assignments found ;
"""


class TimingGateTests(unittest.TestCase):
    def test_constrained_clock_output_is_allowed(self):
        self.assertTrue(check_report(REPORT)["passed"])

    def test_additional_video_output_and_duplicate_engine(self):
        video = "; emu|psram_speed_pll|pll_inst|video|divclk ; Generated ; 29.524 ; 33.87 MHz ;\n"
        report = REPORT.replace("; Clocks ;", "; Clocks ;\n" + video)
        self.assertTrue(check_report(report)["passed"])
        self.assertFalse(check_report(report.replace("video|divclk ; Generated ; 29.524 ; 33.87", "video|divclk ; Generated ; 14.762 ; 67.74"))["passed"])

    def test_engine_and_other_clock_violations_are_rejected(self):
        for value in ("0.353", "0.586", "3.270", "0.927", "1.091"):
            with self.subTest(slack=value):
                result = check_report(REPORT.replace(f"; {value} ;", f"; -{value} ;"))
                self.assertFalse(result["passed"])
                self.assertEqual(len(result["violations"]), 1)

    def test_incomplete_or_invalid_reports_are_rejected(self):
        for report in ("", REPORT.split("; Hold Summary ;")[0],
                       REPORT.replace("; 0.353 ;", "; NaN ;"),
                       REPORT.replace("; 0.353 ;", "; unreadable ;"),
                       REPORT.replace("; Setup Summary ;", "; Setup Summary ;\n; other_clock ; unreadable ; 0.000 ;"),
                       REPORT.replace("; 0.353 ; 0.000 ;", "; 0.353 ; NaN ;"),
                       REPORT.replace("33.87 MHz", "67.74 MHz"),
                       REPORT.replace("67.74 MHz", "33.87 MHz"),
                       REPORT.replace("PSRAM_33M87_CLK_EXT", "Missing_clock")):
            with self.subTest(report=report):
                self.assertFalse(check_report(report)["passed"])

    def test_rounded_negative_slack_and_tns_are_rejected(self):
        self.assertTrue(check_report(REPORT.replace("; 0.353 ;", "; 0.000 ;"))["passed"])
        for row in ("; -0.000 ; 0.000 ;", "; 0.000 ; -0.001 ;",
                    "; 0.000 ; -0.000 ;"):
            with self.subTest(row=row):
                self.assertFalse(check_report(REPORT.replace("; 0.353 ; 0.000 ;", row))["passed"])

    def test_missing_dq_delays_or_ignored_constraints_are_rejected(self):
        for warning in (
            "Warning: Ignored set_input_delay at Saturn_PSRAM_Stress_33M87.sdc(12)",
            "; PSRAM_DQ[3] ; No input delay ;",
            "; PSRAM_CE_N ; No output delay ;",
            "Warning: Ignored set_false_path at Saturn_PSRAM_33M87.sdc(30)",
            "Warning: Ignored set_input_delay at Saturn_PSRAM_33M87.sdc(12)",
        ):
            with self.subTest(warning=warning):
                self.assertFalse(check_report(REPORT + warning)["passed"])


if __name__ == "__main__":
    unittest.main()
