import numpy as np
import os

temp = """&molgw
 scf='hf'
 nspin=1

 basis='cc-pV5Z'
 basis_path='./basis/'

 natom=1
 alpha_mixing=0.5
 mixing_scheme='simple'
 tolscf = 1.0
 nscf   = 1
/
XXX 0.  0.  0.
XXX 0.  0.  2.0
"""

elements = ['H','Li','B','C','N','O','F','Na','Al','Si','P','S','Cl']

for sym in elements:
    inp = temp.replace('XXX', sym)
    with open('molgw.in', 'w') as f: f.write(inp)
    os.system('./molgw molgw.in ')
    
