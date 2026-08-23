Core Pipeline
=============

The 5-stage RV32IM pipeline (IF, ID, EX, MEM, WB), its inter-stage pipeline
registers, and the functional units used within each stage.

Top-Level Core
--------------

.. vhdl:autoentity:: CPU_FPGA

Pipeline Stages
----------------

.. vhdl:autoentity:: IF_Stage

.. vhdl:autoentity:: ID_Stage

.. vhdl:autoentity:: EX_Stage

.. vhdl:autoentity:: mem_stage

Pipeline Registers
-------------------

.. vhdl:autoentity:: IF_ID_Register

.. vhdl:autoentity:: ID_EX_Register

.. vhdl:autoentity:: ex_mem_register

.. vhdl:autoentity:: MEM_WB_Register

Functional Units
-----------------

.. vhdl:autoentity:: ALU

.. vhdl:autoentity:: Control_Unit

.. vhdl:autoentity:: RegFile

.. vhdl:autoentity:: Program_Counter

.. vhdl:autoentity:: ImmGen

.. vhdl:autoentity:: Instruction_Memory

.. vhdl:autoentity:: Data_Memory

.. vhdl:autoentity:: Forwarding_Unit

.. vhdl:autoentity:: Hazard_Unit

.. vhdl:autoentity:: M_Extension_Unit
