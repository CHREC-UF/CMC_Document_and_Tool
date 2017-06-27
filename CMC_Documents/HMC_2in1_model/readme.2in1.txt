Disclaimer of Warranty:
-----------------------
This software code and all associated documentation, comments or other 
information (collectively "Software") is provided "AS IS" without 
warranty of any kind. MICRON TECHNOLOGY, INC. ("MTI") EXPRESSLY 
DISCLAIMS ALL WARRANTIES EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED 
TO, NONINFRINGEMENT OF THIRD PARTY RIGHTS, AND ANY IMPLIED WARRANTIES 
OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE. MTI DOES NOT 
WARRANT THAT THE SOFTWARE WILL MEET YOUR REQUIREMENTS, OR THAT THE 
OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE. 
FURTHERMORE, MTI DOES NOT MAKE ANY REPRESENTATIONS REGARDING THE USE OR 
THE RESULTS OF THE USE OF THE SOFTWARE IN TERMS OF ITS CORRECTNESS, 
ACCURACY, RELIABILITY, OR OTHERWISE. THE ENTIRE RISK ARISING OUT OF USE 
OR PERFORMANCE OF THE SOFTWARE REMAINS WITH YOU. IN NO EVENT SHALL MTI, 
ITS AFFILIATED COMPANIES OR THEIR SUPPLIERS BE LIABLE FOR ANY DIRECT, 
INDIRECT, CONSEQUENTIAL, INCIDENTAL, OR SPECIAL DAMAGES (INCLUDING, 
WITHOUT LIMITATION, DAMAGES FOR LOSS OF PROFITS, BUSINESS INTERRUPTION, 
OR LOSS OF INFORMATION) ARISING OUT OF YOUR USE OF OR INABILITY TO USE 
THE SOFTWARE, EVEN IF MTI HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH 
DAMAGES. Because some jurisdictions prohibit the exclusion or 
limitation of liability for consequential or incidental damages, the 
above limitation may not apply to you.

Copyright 2015 Micron Technology, Inc. All rights reserved.

-------------------------------------------------------------------------------
----------------------------- HMC 2in1 Model ---------------------------------- 
-------------------------------------------------------------------------------
   
Overview:
---------
  The HMC "2in1" model is a co-simulation model that combines the pin-level
  interface of the HMC Bus Functional Model (BFM) with a SystemC performance model. 
  That is, an HMC cube can be wired as the DUT in a hardware simulation while
  providing the modeling accuracy of the HMC SystemC model. 

  This release of the model only supports HMC Gen2 and will only run on an
  x86-64 platform (no 32-bit support). See "Tested Tool Versions" for a list of
  officially supported verilog tool versions.

Prerequisites:
----------------
  
  To compile and run the HMC 2in1 model you will need: 
    - An x86-64 (64 bit) platform 
    - One of the "big three" verilog tools (Mentor Modelsim/Questa, Synopsys VCS,
      Cadence Incisive)
    - A compatible C++ compiler toolchain (will be provided by verilog tool; 
      may require a separate download)
    - A build of the HMC SystemC library, associated headers, and system verilog
      wrapper (provided in this package in the sysc/ directory)

Using the model:
----------------
(The shell commands below assume you are using bash as your shell)

1a.) Make sure that your verilog tool of choice is in your $PATH and any library
    folders are available to the loader (usually through $LD_LIBRARY_PATH).
    If you encounter library linking/loading issues, please see the "Common
    Issues" section below.

1b.) For ease of following this setup procedure, go into the directory that
    contains this file (readme.2in1.txt) and run: 
         source env.sh

    This will add a variable called $BFM_ROOT to your current shell
    environment. This variable will be used in the example commands below.
    
2a.) *******VCS ONLY*********** Download the VCS compiler toolchain
    Synopsys does not package a compatible compiler in their standard
    installation due to size considerations. A compatible version of the compiler
    must be downloaded for free from their servers. See section "Downloading and
    Installing the VG_GNU_PACKAGE" (section 5-7) of the "VCS® MX / VCS® MXi Release
    Notes" document that is included with your VCS distribution for instructions on 
    how to install the compiler toolchain.

    For reference, we provide an example of how to install and run the VCS compiler
    tools below. In this example, we will assume the VCS compiler distribution
    tarball has been downloaded to $BFM_ROOT/sysc/
        cd $BFM_ROOT/sysc/
        mkdir vcs-compiler
        cd vcs-compiler
        tar zxf ../linux_gcc4_default.tar.gz
        cd amd64 
        export VG_GNU_PACKAGE=`pwd`

    You will need to have the $VG_GNU_PACKAGE variable defined to use the 
    sample makefile in the next step. For convenience, we have added the default
    path described in this file to env.sh for you. However, if you choose to 
    install the VCS compiler to a different location, please adjust this path
    in your environment.


2b.) Run one of the commands provided in the example makefile (depending on your toolchain): 
        - Cadence:      make -f makefile.2in1 irun-13.10
								make -f makefile.2in1 irun-14.10
								make -f makefile.2in1 irun-15.20
        - Modelsim:     make -f makefile.2in1 questa			(10.3 and earlier)
								make -f makefile.2in1 questa-10.4	(10.4 )
								make -f makefile.2in1 questa-10.5	(10.5 )

        - Synopsys:
          First, you must make sure that your VG_GNU_PACKAGE environment 
          variable points to the 64 bit compiler in the VCS distribution (See
          step 2a. above for details.)
          
          Then, run the following command:

          (unset LD_LIBRARY_PATH && source $VG_GNU_PACKAGE/source_me_gcc4_64-shared.sh && make -f makefile.2in1 vcs-2014)

			 Replace vcs-2014 with the installed VCS version. Supported targets 
			 are vcs-2013, vcs-2014, vcs-2016.

          Note that the parentheses around this command are important. This
          ensures commands will be run in a sub-shell and will not pollute your
          current shell's environment.
    
         
    The tool should build the SystemC wrapper and the SystemVerilog code,
    elaborate the design, and begin the simulation. A log file is saved to
    run-irun.txt, run-vcs.txt, or run-questa.txt depending on the selected tool.
    
    The default test case issues 10000 random transactions to the 2in1 model and
    waits for all transactions to complete before ending the test case. 

3.) Examine the output logs to make sure the simulation completed.
    A successful simulation will contain a performance summary from the SystemC
    model along with the message "SIMULATION IS COMPLETE".

4.) Using the example makefile, customize the commands to integrate the 2in1
    into your own environment. Since the 2in1 model is an extension of the HMC
    BFM, it should require only minor changes to replace the BFM model with the
    2in1 model as the DUT in your configuration. 

Selecting Tests and Configs:
----------------------------
  The sample 2in1 makefile defaults to running the tests/hmc_rand_req.sv test with
  no configuration files. However, it supports selecting a different test and
  configuration by using the TEST variable at the command line. For example, to 
  run the one write/one read test in Cadence Incisive, you can run: 

    make -f makefile.2in1 irun TEST="tests/hmc_1wr1rd.sv"

  Or, to run the same test with the cfg/hmc_info_msg.sv config using Modelsim, you can run: 

    make -f makefile.2in1 questa TEST="tests/hmc_1wr1rd.sv cfg/hmc_info_msg.sv"

  The same test/configuration for VCS 2014 would look like this: 

    (unset LD_LIBRARY_PATH && source $VG_GNU_PACKAGE/source_me_gcc4_64-shared.sh && make -f makefile.2in1 vcs-2014 TEST="tests/hmc_1wr1rd.sv cfg/hmc_info_msg.sv")

  Note that for the initial release, we have included only a limited number of tests and
  configurations. As we develop a more detailed model and fix bugs in the initial release
  we will add more tests and configurations in later releases. 

  In this release, we have provided an example of how to instantiate multiple
  2in1 instances. This can be enabled by setting the environment variable
  MULTICUBE=1 when running 'make'. For example: 

     MULTICUBE=1 make -f makefile.2in1 questa 

  Note that the multicube instantiation currently only works with the test
  'test/hmc_rand_req_multicube.sv'

  Note, the multicube topology is "flat" (i.e., no chaining) where one host
  talks to several independent cubes. In a real implementation, the host would
  be responsible for knowing which links are connected to which cube and routing
  requests appropriately.

  The multicube test uses hmc_2in1_multicube_bfm.f and
  src/hmc_multicube_bfm_tb.sv to instantiate multiple instances of the normal
  2in1 testbench and routes requests to multiple instances. 

Simulation Parameters: 
----------------------
  Unlike previous releases, token parameters from the BFM are automatically set
  in the SystemC model. This means that setting parameters in config.ini is no 
  longer required for setting token counts. 
  
  A config.ini file can be specified by setting the environment variable
  LIBHMC_CONFIG_FILE with a path to a config.ini. However, it is unlikely this
  will be necessary.
  
Tested Tool Versions: 
---------------------
    -Cadence:    irun(64)    13.10-s008
                 irun(64)    14.10-p001
					  irun(64)    14.10-s011
					  irun(64)    15.20-s006
    -Modelsim:   QuestaSim-64 qverilog 10.3d_3 Compiler 2014.11 Nov 24 2014
	 				  QuestaSim-64 qverilog 10.4d Compiler 2015.12 Dec 29 2015
					  QuestaSim-64 qverilog 10.5c Compiler 2016.07 Jul 20 2016
    -Synopsys:   G-2012.09_Full64
                 H-2013.06
					  J-2014.12-SP3-1

Common Problems: 
----------------
  Due to the complex interactions of C++ shared libraries with the shell
  environment, it is possible to get subtle linker/loader errors at simulation
  runtime. One common source of such errors is the dynamic loading of
  non-vendor-supplied standard libraries such as libgcc or libstdc++. 

  If you get symbol resolution errors, please make sure that the 'ldd'
  indicates that libhmcsim.so's library dependencies point to vendor-supplied
  standard libraries. 

  This is an example of an environment that may cause library loading problems: 

     $ ldd sysc/libhmcsim-questa/lib/libhmcsim.so
             libstdc++.so.6 => /home/user/software/lib64/libstdc++.so.6 (0x00002b80bca36000)
             libgcc_s.so.1 => /home/user/software/lib64/libgcc_s.so.1 (0x00002b80bcebe000)
             libc.so.6 => /lib64/libc.so.6 (0x00002b80bd12e000)
             /lib64/ld-linux-x86-64.so.2 (0x0000003475800000)

  That is, libstdc++.so and libgcc_s.so point to non-vendor locations. However,
  if we prepend the proper library directory to $LD_LIBRARY_PATH: 

     $ export LD_LIBRARY_PATH=/usr/apps/mentor/questasim_10.2c/questa_sim/gcc-4.5.0-linux_x86_64/lib64:$LD_LIBRARY_PATH

  We can confirm that we now have the correct library paths:

     $ ldd sysc/libhmcsim-questa/lib/libhmcsim.so
             libstdc++.so.6 => /usr/apps/mentor/questasim_10.2c/questa_sim/gcc-4.5.0-linux_x86_64/lib64/libstdc++.so.6 (0x00002b822dc88000)
             libgcc_s.so.1 => /usr/apps/mentor/questasim_10.2c/questa_sim/gcc-4.5.0-linux_x86_64/lib64/libgcc_s.so.1 (0x00002b822e115000)
             libc.so.6 => /lib64/libc.so.6 (0x00002b822e385000)
             /lib64/ld-linux-x86-64.so.2 (0x0000003475800000)

  That is, libstdc++.so and libgcc_s.so are now resolved to the correct vendor-supplied version.

Model Status and Limitations:
-----------------------------
  This release of the 2in1 model is beta software. As such, it is highly
  likely to contain bugs and limited accuracy of performance results.  This 
  release is intended as a sample co-simulation implementation to integrate
  into your environment.

  Furthermore, this model has the following limitations: 
    - No support for atomic operations
    - Powering down links during simulation likely produces incorrect
      statistics from the SystemC model
    - Only a subset of tests and configurations are available for this release 
     

Revision History:
----------------

    DATE        REV       NOTE

    03/17/2017  1.1.7     Add new simulator target: Questa 10.5 
                          Accuracy improvements

    11/11/2016  1.1.6     Uses SystemC V2.2 performance model
                          Added fix to start links concurrently
                          Changed BFM to perform nop and issue response w/ERRSTAT rather than
                          enter error abort mode, in good CRC/bad length for command case.
                          Added unsolicited error response packet with ERRSTAT when starting retry.
                          Accuracy improvements

    08/22/2016  1.1.5     Add new simulator targets: VCS 2014, Incisiv 15.20, QuestaSim 10.4
                          Add poison packet support	
                          Fix loading of register default values for mode R/W
                          Fix no error packet generated bug	
                          Fix ModelSim compiler error
