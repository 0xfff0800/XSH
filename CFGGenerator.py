#!/usr/bin/env python3
"""
ARM64 Control Flow Graph Generator
Generates CFG like Hopper Disassembler with Graphviz visualization
"""

import re
from typing import List, Dict, Set, Tuple, Optional
from dataclasses import dataclass
from enum import Enum


class BlockType(Enum):
    """Types of basic blocks"""
    ENTRY = "entry"           # Function entry point
    NORMAL = "normal"         # Regular basic block
    CONDITIONAL = "conditional"  # Ends with conditional branch
    UNCONDITIONAL = "unconditional"  # Ends with unconditional branch
    RETURN = "return"         # Ends with return


class EdgeType(Enum):
    """Types of control flow edges"""
    FALLTHROUGH = "fallthrough"  # Green - natural flow
    CONDITIONAL_TRUE = "conditional_true"  # Red - branch taken
    CONDITIONAL_FALSE = "conditional_false"  # Red - branch not taken
    UNCONDITIONAL = "unconditional"  # Red - unconditional jump
    CALL = "call"  # Blue - function call


@dataclass
class Instruction:
    """Represents a single ARM64 instruction"""
    address: int
    mnemonic: str
    operands: str
    raw_bytes: str = ""

    def __str__(self):
        return f"0x{self.address:x}: {self.mnemonic:8} {self.operands}"

    def is_branch(self) -> bool:
        """Check if instruction is a branch"""
        return self.mnemonic.upper() in [
            'B', 'BR', 'BL', 'BLR',
            'B.EQ', 'B.NE', 'B.CS', 'B.CC', 'B.MI', 'B.PL',
            'B.VS', 'B.VC', 'B.HI', 'B.LS', 'B.GE', 'B.LT',
            'B.GT', 'B.LE', 'B.AL',
            'CBZ', 'CBNZ', 'TBZ', 'TBNZ'
        ]

    def is_conditional_branch(self) -> bool:
        """Check if instruction is a conditional branch"""
        return self.mnemonic.upper() in [
            'B.EQ', 'B.NE', 'B.CS', 'B.CC', 'B.MI', 'B.PL',
            'B.VS', 'B.VC', 'B.HI', 'B.LS', 'B.GE', 'B.LT',
            'B.GT', 'B.LE',
            'CBZ', 'CBNZ', 'TBZ', 'TBNZ'
        ]

    def is_unconditional_branch(self) -> bool:
        """Check if instruction is an unconditional branch"""
        return self.mnemonic.upper() in ['B', 'BR']

    def is_call(self) -> bool:
        """Check if instruction is a function call"""
        return self.mnemonic.upper() in ['BL', 'BLR']

    def is_return(self) -> bool:
        """Check if instruction is a return"""
        return self.mnemonic.upper() == 'RET'

    def get_branch_target(self) -> Optional[int]:
        """Extract branch target address from operands"""
        # Look for hex address pattern (0x...)
        match = re.search(r'0x([0-9a-fA-F]+)', self.operands)
        if match:
            return int(match.group(1), 16)

        # Look for label pattern (loc_...)
        match = re.search(r'loc_([0-9a-fA-F]+)', self.operands)
        if match:
            return int(match.group(1), 16)

        return None


@dataclass
class BasicBlock:
    """Represents a basic block in the CFG"""
    start_address: int
    end_address: int
    instructions: List[Instruction]
    block_type: BlockType = BlockType.NORMAL

    def __str__(self):
        return f"Block 0x{self.start_address:x}-0x{self.end_address:x}"

    def get_id(self) -> str:
        """Get unique identifier for this block"""
        return f"block_{self.start_address:x}"

    def get_label(self) -> str:
        """Get display label for Graphviz"""
        lines = []
        for instr in self.instructions:
            lines.append(f"0x{instr.address:x}: {instr.mnemonic} {instr.operands}")
        return "\\n".join(lines)


@dataclass
class CFGEdge:
    """Represents an edge in the CFG"""
    from_block: BasicBlock
    to_block: BasicBlock
    edge_type: EdgeType

    def __str__(self):
        return f"{self.from_block} -> {self.to_block} ({self.edge_type.value})"


class ControlFlowGraph:
    """Control Flow Graph for an ARM64 function"""

    def __init__(self, function_name: str, start_address: int):
        self.function_name = function_name
        self.start_address = start_address
        self.blocks: List[BasicBlock] = []
        self.edges: List[CFGEdge] = []
        self.block_map: Dict[int, BasicBlock] = {}  # address -> block

    def add_block(self, block: BasicBlock):
        """Add a basic block to the CFG"""
        self.blocks.append(block)
        self.block_map[block.start_address] = block

    def add_edge(self, edge: CFGEdge):
        """Add an edge to the CFG"""
        self.edges.append(edge)

    def get_block_at(self, address: int) -> Optional[BasicBlock]:
        """Get basic block that contains the given address"""
        for block in self.blocks:
            if block.start_address <= address <= block.end_address:
                return block
        return None

    def to_dot(self) -> str:
        """Generate Graphviz DOT format"""
        dot = []
        dot.append(f'digraph "{self.function_name}" {{')
        dot.append('    rankdir=TB;')
        dot.append('    node [shape=box, style=filled, fontname="Courier New"];')
        dot.append('')

        # Add nodes (basic blocks)
        for block in self.blocks:
            # Color based on block type
            if block.block_type == BlockType.ENTRY:
                color = 'lightblue'
            elif block.block_type == BlockType.RETURN:
                color = 'lightcoral'
            elif block.block_type == BlockType.CONDITIONAL:
                color = 'lightyellow'
            else:
                color = 'lightgray'

            label = block.get_label()
            dot.append(f'    {block.get_id()} [label="{label}", fillcolor={color}];')

        dot.append('')

        # Add edges
        for edge in self.edges:
            from_id = edge.from_block.get_id()
            to_id = edge.to_block.get_id()

            # Color and style based on edge type
            if edge.edge_type == EdgeType.FALLTHROUGH:
                # Green - natural flow
                color = 'green'
                style = 'solid'
                label = ''
            elif edge.edge_type in [EdgeType.CONDITIONAL_TRUE, EdgeType.CONDITIONAL_FALSE]:
                # Red - conditional branch
                color = 'red'
                style = 'solid'
                label = 'T' if edge.edge_type == EdgeType.CONDITIONAL_TRUE else 'F'
            elif edge.edge_type == EdgeType.UNCONDITIONAL:
                # Red - unconditional jump
                color = 'red'
                style = 'bold'
                label = ''
            elif edge.edge_type == EdgeType.CALL:
                # Blue - function call
                color = 'blue'
                style = 'dashed'
                label = 'call'
            else:
                color = 'black'
                style = 'solid'
                label = ''

            if label:
                dot.append(f'    {from_id} -> {to_id} [color={color}, style={style}, label="{label}"];')
            else:
                dot.append(f'    {from_id} -> {to_id} [color={color}, style={style}];')

        dot.append('}')
        return '\n'.join(dot)

    def save_dot(self, filename: str):
        """Save CFG to .dot file"""
        with open(filename, 'w') as f:
            f.write(self.to_dot())
        print(f"✅ Saved CFG to {filename}")
        print(f"   To visualize: dot -Tpng {filename} -o {filename.replace('.dot', '.png')}")


class CFGBuilder:
    """Builds Control Flow Graph from ARM64 instructions"""

    def __init__(self, instructions: List[Instruction], function_name: str = "sub_unknown"):
        self.instructions = instructions
        self.function_name = function_name
        self.start_address = instructions[0].address if instructions else 0
        self.cfg = ControlFlowGraph(function_name, self.start_address)
        self.instr_map: Dict[int, Instruction] = {i.address: i for i in instructions}

    def build(self) -> ControlFlowGraph:
        """Build the complete CFG"""
        print(f"Building CFG for {self.function_name} at 0x{self.start_address:x}")

        # Step 1: Identify basic block boundaries
        block_starts = self._find_block_starts()

        # Step 2: Create basic blocks
        blocks = self._create_basic_blocks(block_starts)

        # Step 3: Build edges
        self._build_edges(blocks)

        print(f"✅ CFG complete: {len(self.cfg.blocks)} blocks, {len(self.cfg.edges)} edges")
        return self.cfg

    def _find_block_starts(self) -> Set[int]:
        """Find addresses where basic blocks start"""
        block_starts = {self.start_address}  # Function entry

        for instr in self.instructions:
            # Block starts after any branch
            if instr.is_branch() or instr.is_return():
                next_addr = instr.address + 4
                if next_addr in self.instr_map:
                    block_starts.add(next_addr)

            # Block starts at branch target
            if instr.is_branch():
                target = instr.get_branch_target()
                if target and target in self.instr_map:
                    block_starts.add(target)

        return block_starts

    def _create_basic_blocks(self, block_starts: Set[int]) -> List[BasicBlock]:
        """Create basic blocks from block start addresses"""
        sorted_starts = sorted(block_starts)
        blocks = []

        for i, start in enumerate(sorted_starts):
            # Find end of this block
            if i + 1 < len(sorted_starts):
                # Block ends before next block starts
                end = sorted_starts[i + 1] - 4
            else:
                # Last block ends at last instruction
                end = self.instructions[-1].address

            # Collect instructions in this block
            block_instrs = []
            addr = start
            while addr <= end and addr in self.instr_map:
                block_instrs.append(self.instr_map[addr])
                addr += 4

            if not block_instrs:
                continue

            # Determine block type
            last_instr = block_instrs[-1]
            if start == self.start_address:
                block_type = BlockType.ENTRY
            elif last_instr.is_return():
                block_type = BlockType.RETURN
            elif last_instr.is_conditional_branch():
                block_type = BlockType.CONDITIONAL
            elif last_instr.is_unconditional_branch():
                block_type = BlockType.UNCONDITIONAL
            else:
                block_type = BlockType.NORMAL

            block = BasicBlock(
                start_address=start,
                end_address=block_instrs[-1].address,
                instructions=block_instrs,
                block_type=block_type
            )

            blocks.append(block)
            self.cfg.add_block(block)

        return blocks

    def _build_edges(self, blocks: List[BasicBlock]):
        """Build control flow edges between blocks"""
        for block in blocks:
            last_instr = block.instructions[-1]
            next_addr = last_instr.address + 4

            # Conditional branch: add both taken and fallthrough edges
            if last_instr.is_conditional_branch():
                # Branch taken (red)
                target = last_instr.get_branch_target()
                if target:
                    target_block = self.cfg.get_block_at(target)
                    if target_block:
                        edge = CFGEdge(block, target_block, EdgeType.CONDITIONAL_TRUE)
                        self.cfg.add_edge(edge)

                # Fallthrough (green)
                if next_addr in self.instr_map:
                    fallthrough_block = self.cfg.get_block_at(next_addr)
                    if fallthrough_block:
                        edge = CFGEdge(block, fallthrough_block, EdgeType.CONDITIONAL_FALSE)
                        self.cfg.add_edge(edge)

            # Unconditional branch: add jump edge (red)
            elif last_instr.is_unconditional_branch():
                target = last_instr.get_branch_target()
                if target:
                    target_block = self.cfg.get_block_at(target)
                    if target_block:
                        edge = CFGEdge(block, target_block, EdgeType.UNCONDITIONAL)
                        self.cfg.add_edge(edge)

            # Function call: add call edge (blue) + fallthrough (green)
            elif last_instr.is_call():
                # Note: We don't add edge to called function (would clutter graph)
                # Just add fallthrough to next instruction
                if next_addr in self.instr_map:
                    fallthrough_block = self.cfg.get_block_at(next_addr)
                    if fallthrough_block:
                        edge = CFGEdge(block, fallthrough_block, EdgeType.FALLTHROUGH)
                        self.cfg.add_edge(edge)

            # Return: no outgoing edges
            elif last_instr.is_return():
                pass  # Terminal block

            # Normal instruction: add fallthrough (green)
            else:
                if next_addr in self.instr_map:
                    fallthrough_block = self.cfg.get_block_at(next_addr)
                    if fallthrough_block:
                        edge = CFGEdge(block, fallthrough_block, EdgeType.FALLTHROUGH)
                        self.cfg.add_edge(edge)


# ============================================================================
# EXAMPLE USAGE
# ============================================================================

def example_simple_function():
    """Example: Simple function with if-else"""
    print("\n" + "="*70)
    print("EXAMPLE 1: Simple if-else function")
    print("="*70 + "\n")

    instructions = [
        # Entry
        Instruction(0x100000000, "SUB", "SP, SP, #0x20"),
        Instruction(0x100000004, "STP", "X29, X30, [SP, #0x10]"),

        # Compare
        Instruction(0x100000008, "CMP", "X0, #0"),
        Instruction(0x10000000c, "B.EQ", "loc_100000020"),  # Branch to else

        # If block
        Instruction(0x100000010, "MOV", "X0, #1"),
        Instruction(0x100000014, "B", "loc_100000028"),  # Jump to end

        # Else block
        Instruction(0x100000020, "MOV", "X0, #0"),

        # End
        Instruction(0x100000028, "LDP", "X29, X30, [SP, #0x10]"),
        Instruction(0x10000002c, "ADD", "SP, SP, #0x20"),
        Instruction(0x100000030, "RET", ""),
    ]

    builder = CFGBuilder(instructions, "simple_if_else")
    cfg = builder.build()
    cfg.save_dot("cfg_simple.dot")

    return cfg


def example_loop_function():
    """Example: Function with a loop"""
    print("\n" + "="*70)
    print("EXAMPLE 2: Function with loop")
    print("="*70 + "\n")

    instructions = [
        # Entry
        Instruction(0x100001000, "SUB", "SP, SP, #0x20"),
        Instruction(0x100001004, "STP", "X29, X30, [SP, #0x10]"),

        # Initialize counter
        Instruction(0x100001008, "MOV", "X1, #0"),

        # Loop header
        Instruction(0x10000100c, "CMP", "X1, X0"),
        Instruction(0x100001010, "B.GE", "loc_100001024"),  # Exit loop if i >= n

        # Loop body
        Instruction(0x100001014, "BL", "sub_100002000"),  # Call function
        Instruction(0x100001018, "ADD", "X1, X1, #1"),  # i++
        Instruction(0x10000101c, "B", "loc_10000100c"),  # Jump back to loop header

        # Exit
        Instruction(0x100001024, "LDP", "X29, X30, [SP, #0x10]"),
        Instruction(0x100001028, "ADD", "SP, SP, #0x20"),
        Instruction(0x10000102c, "RET", ""),
    ]

    builder = CFGBuilder(instructions, "loop_function")
    cfg = builder.build()
    cfg.save_dot("cfg_loop.dot")

    return cfg


def example_switch_case():
    """Example: Switch-case statement"""
    print("\n" + "="*70)
    print("EXAMPLE 3: Switch-case function")
    print("="*70 + "\n")

    instructions = [
        # Entry
        Instruction(0x100002000, "SUB", "SP, SP, #0x20"),

        # Switch on X0
        Instruction(0x100002004, "CMP", "X0, #0"),
        Instruction(0x100002008, "B.EQ", "loc_100002020"),  # Case 0

        Instruction(0x10000200c, "CMP", "X0, #1"),
        Instruction(0x100002010, "B.EQ", "loc_100002030"),  # Case 1

        Instruction(0x100002014, "CMP", "X0, #2"),
        Instruction(0x100002018, "B.EQ", "loc_100002040"),  # Case 2

        Instruction(0x10000201c, "B", "loc_100002050"),  # Default

        # Case 0
        Instruction(0x100002020, "MOV", "X0, #100"),
        Instruction(0x100002024, "B", "loc_100002058"),  # Break

        # Case 1
        Instruction(0x100002030, "MOV", "X0, #200"),
        Instruction(0x100002034, "B", "loc_100002058"),  # Break

        # Case 2
        Instruction(0x100002040, "MOV", "X0, #300"),
        Instruction(0x100002044, "B", "loc_100002058"),  # Break

        # Default
        Instruction(0x100002050, "MOV", "X0, #-1"),

        # End
        Instruction(0x100002058, "ADD", "SP, SP, #0x20"),
        Instruction(0x10000205c, "RET", ""),
    ]

    builder = CFGBuilder(instructions, "switch_case")
    cfg = builder.build()
    cfg.save_dot("cfg_switch.dot")

    return cfg


def example_nested_conditions():
    """Example: Nested if conditions"""
    print("\n" + "="*70)
    print("EXAMPLE 4: Nested conditions")
    print("="*70 + "\n")

    instructions = [
        # Entry
        Instruction(0x100003000, "SUB", "SP, SP, #0x20"),

        # if (x > 0)
        Instruction(0x100003004, "CMP", "X0, #0"),
        Instruction(0x100003008, "B.LE", "loc_100003030"),  # else

        # if (x > 10)
        Instruction(0x10000300c, "CMP", "X0, #10"),
        Instruction(0x100003010, "B.LE", "loc_100003020"),  # else inner

        # x > 10
        Instruction(0x100003014, "MOV", "X0, #2"),
        Instruction(0x100003018, "B", "loc_100003038"),  # exit

        # 0 < x <= 10
        Instruction(0x100003020, "MOV", "X0, #1"),
        Instruction(0x100003024, "B", "loc_100003038"),  # exit

        # x <= 0
        Instruction(0x100003030, "MOV", "X0, #0"),

        # Exit
        Instruction(0x100003038, "ADD", "SP, SP, #0x20"),
        Instruction(0x10000303c, "RET", ""),
    ]

    builder = CFGBuilder(instructions, "nested_conditions")
    cfg = builder.build()
    cfg.save_dot("cfg_nested.dot")

    return cfg


# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    print("""
╔══════════════════════════════════════════════════════════════════╗
║         ARM64 Control Flow Graph Generator                       ║
║         Like Hopper Disassembler                                 ║
╚══════════════════════════════════════════════════════════════════╝
""")

    # Run all examples
    example_simple_function()
    example_loop_function()
    example_switch_case()
    example_nested_conditions()

    print("\n" + "="*70)
    print("ALL CFGs GENERATED!")
    print("="*70)
    print("\nTo visualize:")
    print("  dot -Tpng cfg_simple.dot -o cfg_simple.png")
    print("  dot -Tpng cfg_loop.dot -o cfg_loop.png")
    print("  dot -Tpng cfg_switch.dot -o cfg_switch.png")
    print("  dot -Tpng cfg_nested.dot -o cfg_nested.png")
    print("\nOr view interactively:")
    print("  xdot cfg_simple.dot")
    print("\n✨ Enjoy your CFGs! 🎉\n")
