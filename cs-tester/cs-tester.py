#!/usr/bin/env python3

# 
# This file originates from Kite's Circuit Sword control board project.
# Author: Kite (Giles Burgess)
# 
# THIS HEADER MUST REMAIN WITH THIS FILE AT ALL TIMES
#
# This firmware is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This firmware is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this repo. If not, see <http://www.gnu.org/licenses/>.
#

# Setup
#############################

GPIO = None  # Imported and initialized only when running on the handheld.
import subprocess
import time
import datetime
import os.path

bindir = os.path.dirname(os.path.abspath(__file__)) + os.sep

# Hardware variables
pi_shdn = 37

class bcolors:
  HEADER = '\033[95m'
  OKBLUE = '\033[94m'
  OKGREEN = '\033[92m'
  WARNING = '\033[93m'
  FAIL = '\033[91m'
  ENDC = '\033[0m'
  BOLD = '\033[1m'
  UNDERLINE = '\033[4m'


# Test for USB devices
#############################
def testUSB():
  lsusb = subprocess.check_output(["/usr/bin/lsusb"], universal_newlines=True)
  print("LSUSB OUTPUT: \n" + str(lsusb) + "\n\n")

  if "Atmel Corp." in lsusb:
    print(bcolors.OKGREEN + "USB ARDUINO = [ OK ]" + bcolors.ENDC)
  else:
    if "Leonardo" in lsusb:
      print(bcolors.OKGREEN + "USB ARDUINO = [ OK ]" + bcolors.ENDC)
    else:
      print(bcolors.FAIL + "USB ARDUINO = [FAIL]" + bcolors.ENDC)

  if "C-Media Electronics" in lsusb:
    print(bcolors.OKGREEN + "USB AUDIO   = [ OK ]" + bcolors.ENDC)
  else:
    print(bcolors.FAIL + "USB AUDIO   = [FAIL]" + bcolors.ENDC)

  if "erminus Technology Inc" in lsusb:
    print(bcolors.OKGREEN + "USB HUB     = [ OK ]" + bcolors.ENDC)
  else:
    print(bcolors.FAIL + "USB HUB     = [FAIL]" + bcolors.ENDC)
  
  if os.path.exists("/dev/input/js0"):
    print(bcolors.OKGREEN + "JOYSTICK    = [ OK ]" + bcolors.ENDC)
  else:
    print(bcolors.FAIL + "JOYSTICK    = [FAIL]" + bcolors.ENDC)

# Test GPIO
#############################
def testGPIO():
  shdnstate = not GPIO.input(pi_shdn)
  if (shdnstate):
    print(bcolors.FAIL + "GPIO SHDN   = [ OFF]" + bcolors.ENDC)
  else:
    print(bcolors.OKGREEN + "GPIO SHDN   = [ ON ]" + bcolors.ENDC)

# Test LCD
#############################
def testLCD():
  print(bcolors.OKBLUE + "TEST LCD.." + bcolors.ENDC)
  pngview_proc = subprocess.Popen([bindir + "pngview", "-l", "99999", bindir + "COLOUR.png", "-x", "0", "-y", "0"])
  time.sleep(1)
  pngview_poll = pngview_proc.poll()
  if (pngview_poll):
    print("ERROR: Failed to start PNGVIEW, got return code [" + str(pngview_poll) + "]\n")
  else:
    time.sleep(3)
    pngview_proc.terminate()

# Test AUDIO
#############################
def testAUDIO():
  print(bcolors.OKBLUE + "TEST AUDIO L.." + bcolors.ENDC)
  aplay_proc = subprocess.Popen(["aplay", bindir + "audiocheck_l.wav"])
  time.sleep(2)
  print(bcolors.OKBLUE + "TEST AUDIO R.." + bcolors.ENDC)
  aplay_proc = subprocess.Popen(["aplay", bindir + "audiocheck_r.wav"])
  time.sleep(2)

# LOGIC
#############################
def main():
  global GPIO
  import RPi.GPIO as GPIO
  GPIO.setwarnings(False)
  GPIO.setmode(GPIO.BCM)
  GPIO.setup(pi_shdn, GPIO.IN)
  print("INFO: Started.\n")
  try:
    while True:
      print("\n\n\n------------------------------")
      print(datetime.datetime.now().time())
      print("------------------------------")
      testUSB()
      testGPIO()
      time.sleep(3)
      testLCD()
      #testAUDIO()
      time.sleep(1)
  except KeyboardInterrupt:
    print("Quitting..")
  finally:
    GPIO.cleanup()


if __name__ == '__main__':
  main()
