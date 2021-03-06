"""Abstract modular synth"""

import random
# import smbus
import time
import sys
import traceback
import serial
# import RPi.GPIO as GPIO
import OSC
import time, random

#
# Some important concepts.
# There are port numbers. These are the numbers used in Arduino
# hardware specification.
# There are port ids. These are numbers attached to ports starting with
# 0 for the first port, 1 for the second and so on.
# Port ids are smaller than port numbers reducing the number of bits that need
# to be sent.
# The comments might not be consistent yet.
#

def union(a, b):
    return list(set(a) | set(b))

def send_free_message(client, nodeID):
    msg = OSC.OSCMessage()
    msg.setAddress("/n_free")
    msg.append(nodeID)
    client.send(msg)

def send_create_synth(client, synthDefName, nodeID):
    msg = OSC.OSCMessage()
    msg.setAddress("/s_new")
    msg.append(synthDefName)
    msg.append(nodeID)
    client.send(msg)

def send_set(client, a, b, c):
    msg = OSC.OSCMessage()
    msg.setAddress("/set")
    msg.append(a)
    msg.append(b)
    msg.append(c)
    client.send(msg)
    # print "Sending", msg

def send_message(client, message):
    # oscsend 127.0.0.1 57110 /n_map isi 1000 freq <msg>
    msg = OSC.OSCMessage()
    msg.setAddress("/n_map")
    msg.append(1000)
    msg.append("freq")
    msg.append(message)
    client.send(msg)
    print "Sending", message

def send_recompile(client):
    msg = OSC.OSCMessage()
    msg.setAddress("/recompile")
    print "Sending", msg
    client.send(msg)

def send_connect(client, a, b, c, d):
    msg = OSC.OSCMessage()
    msg.setAddress("/connect")
    msg.append(a)
    msg.append(b)
    msg.append(c)
    msg.append(d)
    client.send(msg)
    print "Sending", msg
    send_recompile(client)

def send_disconnect(client, a, b):
    msg = OSC.OSCMessage()
    msg.setAddress("/disconnect")
    msg.append(a)
    msg.append(b)
    client.send(msg)
    print "Sending", msg
    send_recompile(client)

#    oscsend 127.0.0.1 57110 /n_map isi 1004 freq 3

#     msg = OSC.OSCMessage()
#     msg.setAddress("/print")
#     msg.append(message)
#     client.send(msg)
#     print "Sending", message

# PROTOCOL_RESET could clash with genuine sending of 255

DELAY = 0.0002
PROTOCOL_RESET = 255
PROTOCOL_WRITE = 0
PROTOCOL_READ = 1
PROTOCOL_WRITE_ALL = 2
PROTOCOL_READ_ALL = 3
PROTOCOL_WRITES = 4
PROTOCOL_ECHO = 5
PROTOCOL_READ_ANALOGUE = 6
PROTOCOL_MODE_INPUT = 7
PROTOCOL_MODE_PULLUP = 8
PROTOCOL_MODE_OUTPUT = 9

class Network(object):
    """Real network"""
    def __init__(self, input_slaves, output_slaves, analogue_slaves, inputs, outputs, analogues, verbose = False):
        self.input_slaves = input_slaves
        self.output_slaves = output_slaves
        self.analogue_slaves = analogue_slaves
        self.inputs = inputs
        self.outputs = outputs
        self.analogues = analogues
	# self.bus = smbus.SMBus(1)
	self.verbose = verbose
        self.bytes_out = 0
        self.bytes_in = 0
        self.dev = {
            4: "/dev/cu.usbmodem14251",
            5: "/dev/cu.usbmodem14261",
            6: "/dev/cu.usbmodem14271"
            }
        self.ports = {}
        for slave in union(union(input_slaves, output_slaves), analogue_slaves):
            print "Opening port", self.dev[slave]
            self.ports[slave] = serial.Serial(self.dev[slave], 115200)
            print "Opened"
            for i in range(4):
                self.writebyte(slave, PROTOCOL_RESET)
                time.sleep(DELAY)

        for input_slave in input_slaves:
            for input_pin in self.inputs[input_slave]:
                self.set_pullup_mode(input_slave, input_pin)
        for output_slave in output_slaves:
            for output_pin in self.outputs[output_slave]:
                self.set_output_mode(output_slave, output_pin)
        for analogue_slave in analogue_slaves:
            for analogue_pin in self.analogues[analogue_slave]:
                self.set_input_mode(analogue_slave, analogue_pin)

    def get_list_of_slaves(self):
        """Get list of all slaves on bus"""
        return self.slaves

    def get_input_list(self, slave):
        """Ask slave for its list of inputs"""
        return self.inputs[slave]

    def get_output_list(self, slave):
        """Ask slave for its list of outputs"""
        return self.outputs[slave]

    def writebyte(self, slave, byte):
        self.ports[slave].write(chr(byte))
        time.sleep(DELAY)
        self.bytes_out += 1

    def readbyte(self, slave):
        c = self.ports[slave].read(1)
        self.bytes_in += 1
        return ord(c)

    def readknob(self, slave, input_pin):
        self.writebyte(slave, PROTOCOL_READ_ANALOGUE)
        # time.sleep(DELAY)
        self.writebyte(slave, input_pin)
        # time.sleep(DELAY)
        return self.readbyte(slave)

    def set_input_mode(self, slave, input_pin):
        self.writebyte(slave, PROTOCOL_MODE_INPUT)
        self.writebyte(slave, input_pin)

    def set_pullup_mode(self, slave, input_pin):
        self.writebyte(slave, PROTOCOL_MODE_PULLUP)
        self.writebyte(slave, input_pin)

    def set_output_mode(self, slave, output_pin):
        self.writebyte(slave, PROTOCOL_MODE_OUTPUT)
        self.writebyte(slave, output_pin)

    def set_slave_all_outs(self, slave, value):
        """Set all outputs to given value for selected slave"""
	if self.verbose:
	    print "Setting slave", slave, "all outputs to", value
	while True:
            try:
	        #self.writebyte(slave, PROTOCOL_RESET)
	        #time.sleep(DELAY)
	        self.writebyte(slave, PROTOCOL_WRITE_ALL)
	        #time.sleep(DELAY)
	        self.writebyte(slave, value)
	        #time.sleep(DELAY)
	        return
            except IOError as err:
                # GPIO.output(18, False)
                # GPIO.output(18, True)
		print "IOError", err
		sys.exit(1)
                pass

    # Each output port is is set according to whether the port id
    # contains bits given in `bit_mask`.
    def set_slave_outs(self, slave, bit_mask):
        """Set all outputs for selected slave"""
	if self.verbose:
	    print "Setting slave", slave, "outputs to mask", value
	while True:
            try:
	        #self.writebyte(slave, PROTOCOL_RESET)
	        #time.sleep(DELAY)
	        self.writebyte(slave, PROTOCOL_WRITES)
	        #time.sleep(DELAY)
	        self.writebyte(slave, bit_mask & 255)
	        self.writebyte(slave, bit_mask >> 8)
                #print "Setting ", "{0:b}".format(bit_mask & 255)
                #print "Setting ", "{0:b}".format(bit_mask >> 8)
	        #time.sleep(DELAY)
	        return
            except IOError as err:
                # GPIO.output(18, False)
                # GPIO.output(18, True)
		print "IOError", err
		sys.exit(1)
                pass

    def get_slave_all_ins(self, slave):
        """Get all inputs from selected slave"""
	while True:
            try:
	        #self.writebyte(slave, PROTOCOL_RESET)
	        #time.sleep(DELAY)
		self.writebyte(slave, PROTOCOL_READ_ALL)
		#time.sleep(DELAY)
		value_lo = self.readbyte(slave)
		value_hi = self.readbyte(slave)
                value = value_lo | (value_hi << 8)
		if self.verbose:
		    print "Read from slave:", value
		return value
	    except IOError as err:
                # GPIO.output(18, False)
                # GPIO.output(18, True)
		print "IOError", err
		sys.exit(1)
		pass


# Assuming no more than 16 inputs and 16 outputs on one module
IO_ADDRESS_WIDTH = 5
INPUT_RANGE = range(1 << IO_ADDRESS_WIDTH)
SLAVE_ADDRESS_WIDTH = 4
SLAVE_RANGE = range(1 << SLAVE_ADDRESS_WIDTH)
MAX_SLAVE = (1 << SLAVE_ADDRESS_WIDTH)-1

# Connection: 8 bit slave, 8 bit inp/output
def get_connectivity(net, input_slaves, output_slaves, inputs, outputs):
    """Get entire connectivity graph"""
    # print "inputs=", inputs
    inputs = {slave: {inp: 0 for inp in inputs[slave]}
                     for slave in input_slaves}

    for slave_bit in range(SLAVE_ADDRESS_WIDTH):
        # Every slave whose address has slave_bit set sets all of
        # of its outputs to 0, otherwise they are all set to 1.

        for output_slave in output_slaves:
            if output_slave & (1 << slave_bit):
                # print "output slave", output_slave, "has all outs = 0"
                net.set_slave_all_outs(output_slave, 0)
                time.sleep(DELAY)
            else:
                # print "Switching off outputs from", slave
                # print "output slave", output_slave, "has all outs = 1"
                net.set_slave_all_outs(output_slave, 1)
                time.sleep(DELAY)

        # print "Checking all slave inputs"
        for input_slave in input_slaves:
            input_bits = net.get_slave_all_ins(input_slave)
            # print "input slave", input_slave, "got inputs", input_bits
            for i, inp in enumerate(inputs[input_slave]):
                # value = net.get_slave_in(slave, inp)
                # print "input slave", slave, "got", value, "on", inp
                if not (input_bits & (1 << i)):
                    address = 1 << (slave_bit+IO_ADDRESS_WIDTH)
                    # print "address =", address
                    inputs[input_slave][inp] += address

    # Switch on matching output for every slave
    # print "Inputs"
    for io_bit in range(IO_ADDRESS_WIDTH):
        # print "io_bit=",io_bit
        for output_slave in output_slaves:
            output_mask = 0
            mask_bit = 1
            for output in outputs[output_slave]:
                if not (output & (1 << io_bit)):
                    output_mask |= mask_bit
                mask_bit <<= 1
            net.set_slave_outs(output_slave, output_mask)
            # print "output_slave=",output_slave, "output_mask=","{0:b}".format(output_mask)
            time.sleep(0.0001)

        for input_slave in input_slaves:
            input_bits = net.get_slave_all_ins(input_slave)
            # print "input_slave=",input_slave, "input_bits=", "{0:b}".format(input_bits)
            for i, inp in enumerate(inputs[input_slave]):
                if not (input_bits & (1 << i)):
                    address = 1 << io_bit
                    # print slave, "got 1 input on", inp, "adding", address
                    inputs[input_slave][inp] += address

    result = {slave: {inp: (value/(1 << IO_ADDRESS_WIDTH),
                          value % (1 << IO_ADDRESS_WIDTH))
                         for inp, value in inputs[slave].items()
                         for input_slave in [value/(1 << IO_ADDRESS_WIDTH)]
                         for input_inp in [value % (1 << IO_ADDRESS_WIDTH)]
                         if input_slave > 0}
              for slave in inputs}
    print result
    return result

def non_empy_list_of_elements(elems):
    while True:
        collection = [elem for elem in elems if random.random() < 0.5]
        if collection:
            return collection


# This function does no I/O. It makes deductions from connectivity graphs
# built by functions that use I/O.
def changes(client, old_connectivity, connectivity):
#     in_out_map = {
#         (5, 11): ('id5', 'result'), # vco square
#         (5, 10): ('id7', 'result'), # vco saw
#         (5, 9): ('id8', 'result'), # vco sin
#         (4, 18): ('ladder22', 'signal'), # ladder in
#         (5, 8): ('ladder22', 'result'), # ladder out
#         (4, 19): ('vca26', 'signal'), # vca in
#     }
    in_out_map = {
        (4, 12): ('in-1', 'signal'), 
        (4, 11): ('in-2', 'signal'), 
        (4, 10): ('in-3', 'signal'), 
        (4, 9): ('in-4', 'signal'), 
        (4, 8): ('in-5', 'signal'), 
        (4, 7): ('in-6', 'signal'), 
        (4, 6): ('in-7', 'signal'), 
        (4, 5): ('in-8', 'signal'), 
        (4, 4): ('in-9', 'signal'), 
        (4, 3): ('in-10', 'signal'), 
        (4, 2): ('in-11', 'signal'), 
        (4, 18): ('in-12', 'signal'), 
        (4, 19): ('in-25', 'signal'), 
        (4, 20): ('in-26', 'signal'), 
        (4, 21): ('in-27', 'signal'), 
        (4, 22): ('in-28', 'signal'), 

        (5, 12): ('out-13', 'result'),
        (5, 11): ('out-14', 'result'),
        (5, 10): ('out-15', 'result'),
        (5, 9): ('out-16', 'result'),
        (5, 8): ('out-17', 'result'),
        (5, 7): ('out-18', 'result'),
        (5, 6): ('out-19', 'result'),
        (5, 5): ('out-20', 'result'),
        (5, 4): ('out-21', 'result'),
        (5, 3): ('out-22', 'result'),
        (5, 2): ('out-23', 'result'),
        (5, 18): ('out-24', 'result'), 
        (5, 19): ('out-29', 'result'),
        (5, 20): ('out-30', 'result'),
        (5, 21): ('out-31', 'result'),
        (5, 22): ('out-32', 'result')
    }

    for slave, inputs in old_connectivity.iteritems():
        for input_number, input_output in inputs.iteritems():
            # print "connectivity[slave] =", connectivity[slave]
            if not connectivity[slave].has_key(input_number):
                print "*", slave, input_number, "disconnected"
                if in_out_map.has_key((slave, input_number)):
                    (in_module, in_input) = in_out_map[(slave, input_number)]
                    print "1.disconnect"
                    send_disconnect(client, in_module, in_input)
            elif connectivity[slave][input_number] != input_output:
                print "*", slave, input_number, "reconnected from", connectivity[slave][input_number]
                if in_out_map.has_key((slave, input_number)):
                    (in_slave, in_number) = connectivity[slave][input_number]
                    (in_module, in_input) = in_out_map[(slave, input_number)]
                    if in_out_map.has_key((in_slave, in_number)):
                        (out_module, out_output) = in_out_map[(in_slave, in_number)]
                        print "2.connect"
                        send_connect(client, out_module, out_output, in_module, in_input)
                    else:
                        print "3.disconnect"
                        send_disconnect(client, in_module, in_input)
    for slave, inputs in connectivity.iteritems():
        # print "slave,inputs=", slave, inputs
        for input_number, input_output in inputs.iteritems():
            # print "input_number, input_output =", input_number, input_output
            # print "old_connectivity =", old_connectivity
            # print "old_connectivity[slave] =", old_connectivity[slave]
            if not old_connectivity[slave].has_key(input_number):
                print "*", slave, input_number, "newly connected from", connectivity[slave][input_number]
                #print "Looking up", slave, input_number, "in in_out_map"
                if in_out_map.has_key((slave, input_number)):
                    (in_slave, in_number) = connectivity[slave][input_number]
                    if in_out_map.has_key((in_slave, in_number)):
                        (out_module, out_output) = in_out_map[(in_slave, in_number)]
                        (in_module, in_input) = in_out_map[(slave, input_number)]
                        print "4.connect"
                        send_connect(client, out_module, out_output, in_module, in_input)
                    else:
                        (in_module, in_input) = in_out_map[(slave, input_number)]
                        print "5.disconnect"
                        send_disconnect(client, in_module, in_input)

def rescale(c, d, a, b, x):
    return a+(x-c)/(d-c)*(b-a)

def main():
    """Main"""
    client = OSC.OSCClient()
    client.connect(('127.0.0.1', 7777))

    input_slaves = [4]
    output_slaves = [5]
    analogue_slaves = [6]
    # Mapping from port ids to port numbers.
    inputs = {4: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 18, 19, 20, 21, 22]}
    outputs = {5: [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 18, 19, 20, 21, 22]}
    analogues = {6: [18, 19, 20, 21, 22, 23, 24, 25]}

    net = Network(input_slaves=input_slaves,
                  output_slaves=output_slaves,
                  analogue_slaves=analogue_slaves,
    		  inputs=inputs,
    		  outputs=outputs,
                  analogues=analogues,
                  verbose=False)
    inputs = {}
    outputs = {}
    for input_slave in input_slaves:
        inputs[input_slave] = net.get_input_list(input_slave)
    for output_slave in output_slaves:
        outputs[output_slave] = net.get_output_list(output_slave)

    while False:
        print "Off"
        net.set_slave_outs(5, 0);
        print net.get_slave_all_ins(4)
        print "On"
        net.set_slave_outs(5, 65535);
        print net.get_slave_all_ins(4)
        time.sleep(1.0)

    last_message = 0

    connectivity = {4: {}, 5: {}, 6: {}} # XXX
    physical_connectivity = {4: {}, 5: {}, 6: {}} # XXX
    knob_pins = [18, 19, 20, 21, 22, 23, 24, 25]
    oldknobs = [-1.0 for k in knob_pins]
    knob_targets = {
        (18, 'knob-1', 'result', (0.0, 1.0)),
        (19, 'knob-2', 'result', (0.0, 1.0)),
        (20, 'knob-3', 'result', (0.0, 1.0)),
        (21, 'knob-4', 'result', (0.0, 1.0)),
        (22, 'knob-5', 'result', (0.0, 1.0)),
        (23, 'knob-6', 'result', (0.0, 1.0)),
        (24, 'knob-7', 'result', (0.0, 1.0)),
        (25, 'knob-8', 'result', (0.0, 1.0))
        #(19, 'input36', 'result', (0.0, 0.25)),
        #(20, 'input41', 'result', (0.0, 0.02)),
        #(21, 'input43', 'result', (0.0, 1.0)),
        #(22, 'input434', 'result', (0.0, 1.0)),
        #(23, 'input435', 'result', (0.0, 1.0))
    }

    while True:
        i = 0
        for (k, a, b, (lo, hi)) in knob_targets:
            value = net.readknob(6, k)
            if abs(value-oldknobs[i]) > 0.01:
                rescaled = rescale(0.0, 255.0, lo, hi, value)
                print value, rescaled
                send_set(client, a, b, rescaled)
                oldknobs[i] = value
            i = i+1

        previous_connectivity = connectivity
	try:
            # Need same result twice in a row to trust it
                connectivity = get_connectivity(net, input_slaves, output_slaves, inputs, outputs)
                if connectivity==previous_connectivity and connectivity!=physical_connectivity:
                    changes(client, physical_connectivity, connectivity)
                    physical_connectivity = connectivity
                # print connectivity
                # print net.bytes_out, net.bytes_in
        except IOError as err:
	    print "Failed for some reason:", err
	    traceback.print_exc(file=sys.stdout)


if __name__ == "__main__":
    main()
