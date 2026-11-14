module testdata_const_narrowing_overflow;

fn void narrowing_casts()
{
	char too_large_char = (char)100000; // want "out of range for cast target 'char'"
	ichar too_large_ichar = (ichar)128; // want "out of range for cast target 'ichar'"
	short too_large_short = (short)32768; // want "out of range for cast target 'short'"
	int too_large_int = (int)2147483648; // want "out of range for cast target 'int'"
	char fits_char = (char)255;
	ichar fits_ichar = (ichar)127;
	short fits_short = (short)32767;
	ushort fits_ushort = (ushort)65535;
	int fits_int = (int)2147483647;
}
