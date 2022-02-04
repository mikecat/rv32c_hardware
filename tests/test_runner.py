import sys
import tempfile
import glob
import os
import os.path
import hashlib
import shutil
import logging
import subprocess

import chromedriver_binary
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.support.select import Select
from selenium.common.exceptions import TimeoutException

# configuration
asm15_url = "https://mikecat.github.io/asm15/"
runnerName = "vvp"
testeeName = "compiled.out"
programName = "prog.txt"
caseDirName = "testcases"
cacheDirName = "testcase_cache"
testeeMemorySize = 1024

# get arguments
if len(sys.argv) < 3:
	name = os.path.basename(sys.argv[0]) if len(sys.argv) > 0 else "test_runner.py"
	sys.error.write("Usage: python " + name + " testeeFile testLevel" + "\n")
	sys.exit(-1)

testeeFile = os.path.abspath(sys.argv[1])
testLevel = int(sys.argv[2])

scriptDir = os.path.dirname(sys.argv[0])

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
logHandler = logging.StreamHandler(sys.stdout)
logHandler.setLevel(logging.INFO)
logFormatter = logging.Formatter("%(levelname)s: %(message)s")
logHandler.setFormatter(logFormatter)
logger.addHandler(logHandler)

# assemble updated test cases
logger.info("checking testcase caches")
os.chdir(os.path.join(scriptDir, caseDirName))
testcases = glob.glob("[0-9][0-9]_*.in.txt")
testcase_caches = []
testcases_to_assemble = []
for t in testcases:
	with open(t, "rb") as f:
		data = f.read()
		hash = hashlib.sha1(data).hexdigest()[0:8]
		caseName, ext = os.path.splitext(t)
		cacheName = "%s.%s%s" % (caseName, hash, ext)
		cachePath = os.path.join(scriptDir, cacheDirName, cacheName)
		testcase_caches.append(cachePath)
		if not os.path.exists(cachePath):
			testcases_to_assemble.append((t, data, cacheName))

if len(testcases_to_assemble) > 0:
	errorOccured = False
	cacheDir = os.path.join(scriptDir, cacheDirName)
	if not os.path.exists(cacheDir):
		os.mkdir(cacheDir)
	os.chdir(cacheDir)
	logger.info("initializing assembler")
	# open Chrome
	options = webdriver.ChromeOptions()
	options.add_argument("--headless")
	with webdriver.Chrome(options=options) as driver:
		# open asm15
		driver.get(asm15_url)

		# set start address
		txtadr = driver.find_element(By.ID, "txtadr")
		txtadr.clear()
		txtadr.send_keys("0")

		# set output format
		selfmt = driver.find_element(By.ID, "selfmt")
		selfmt_selobj = Select(selfmt)
		selfmt_selobj.select_by_visible_text("binary")

		def assemble(asm_source):
			# set assembly source
			textarea_asm = driver.find_element(By.ID, "textarea1")
			textarea_asm.clear()
			textarea_asm.send_keys(asm_source)

			# assemble
			assemble_button = driver.find_element(By.ID, "submit-button")
			assemble_button.click()

			# get errors from alert dialog(s)
			errors = ""
			wait = WebDriverWait(driver, 1)
			while True:
				try:
					alert = wait.until(EC.alert_is_present())
				except TimeoutException:
					break
				errors += alert.text + "\n"
				alert.accept()

			# get assembled result
			textarea_res = driver.find_element(By.ID, "textarea2")
			res = textarea_res.get_attribute("value")
			return res, errors

		for name, data, cachePath in testcases_to_assemble:
			logger.info("assembling " + name)
			result, errors = assemble(data.decode("UTF-8"))
			if errors != "":
				logger.error("assemble error for " + name + ":\n" + errors)
				errorOccured = True
			else:
				# remove old cache(s)
				caseName, ext = os.path.splitext(name)
				oldCaches = glob.glob(caseName + ".*" + ext)
				for oc in oldCaches:
					os.remove(oc)
				# convert result to full memory data
				resultArray = result.replace("\r\n", "\n").replace("\r", "\n").rstrip().split("\n")
				finalResultArray = []
				key1, key2 = "*** ", "-byte gap ***"
				errorFoundForThisFile = False
				for word in resultArray:
					if (word[:len(key1)] == key1) and (word[-len(key2):] == key2):
						gapSize = int(word[len(key1):-len(key2)])
						if gapSize % 2 != 0:
							logger.error("odd-sized gap found for " + name)
							errorOccured = True
							errorFoundForThisFile = True
						finalResultArray += ["0" * 16] * (gapSize // 2)
					else:
						finalResultArray.append(word)
				if len(finalResultArray) > testeeMemorySize:
					logger.error("assembly result too large for " + name + (" (%d/%d)" % (len(finalResultArray), testeeMemorySize)))
					errorOccured = True
				elif not errorFoundForThisFile:
					finalResultArray += ["0" * 16] * (testeeMemorySize - len(finalResultArray))
					finalResult = "\n".join(finalResultArray) + "\n"
					# save result
					with open(cachePath, "w") as f:
						f.write(finalResult)
	if errorOccured:
		sys.exit(-1)

# run tests
testCount = 0
failCount = 0
with tempfile.TemporaryDirectory() as workDir:
	logger.info("starting tests")
	os.chdir(workDir)
	try:
		shutil.copy(testeeFile, testeeName)
		for name, inputFile in zip(testcases, testcase_caches):
			caseLevel = int(name.split("_")[0], 10)
			if caseLevel <= testLevel:
				testCount += 1
				logger.info("testing " + name)
				shutil.copy(inputFile, programName)
				result = subprocess.run([runnerName, testeeName], capture_output=True)
				resultLines = [l for l in result.stdout.decode("UTF-8").replace("\r\n", "\n").replace("\r", "\n").rstrip().split("\n") if ":" not in l]
				caseName, ext = os.path.splitext(name)
				trueCaseName, _ = os.path.splitext(caseName)
				with open(os.path.join(scriptDir, caseDirName, trueCaseName + ".out.txt"), "r") as expectedFile:
					expected = expectedFile.read().replace("\r\n", "\n").replace("\r", "\n").rstrip().split("\n")
					if resultLines != expected:
						logger.warning("test " + name + " failed!")
						logger.warning("expected: " + str(expected))
						logger.warning("actual  : " + str(resultLines))
						failCount += 1
	finally:
		os.chdir(scriptDir)

logger.info("%d test(s) passed, %d test(s) failed" % (testCount - failCount, failCount))
if failCount > 0:
	sys.exit(1)
