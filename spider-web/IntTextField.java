import java.awt.*;

public class IntTextField extends TextField
{

	public IntTextField()
	{
		;
	}
	
	public IntTextField(String s) 
	{
		this.setText(s);
	}
	
	public boolean isValid()
	{
		int value;
		try
		{
			value = Integer.valueOf(getText().trim()).intValue();

		}
		catch (NumberFormatException e)
		{
			requestFocus();
			return false;
		}
		return true;
	}
	
	public int getValue()
	{
		return Integer.parseInt(getText().trim(),10);
	}
}
