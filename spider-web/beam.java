import java.awt.*;

public class beam extends Dialog 
{
	public beam(spiderframe parent, String Prefix, Font font) {
		super(parent, "Call/Prefix/Other", true);
		this.parent = parent;
		this.setFont(font);
								
		Panel p1 = new Panel();
		p1.setLayout(new GridLayout(2,2));
		p1.add(new Label("Enter Your Choice (Call/Prefix/Other) "));
		p1.add(prefix = new TextField(Prefix, 6));
		add("Center", p1);
		
		Panel p2 = new Panel();
		p2.add(new Button("OK"));
		p2.add(new Button("Cancel"));
		add("South", p2);
		
		resize(280,120);
		show();
	}
	
	public boolean action(Event evt, Object arg) {
		if (arg.equals("OK")) {
			dispose();
			parent.setPrefix(prefix.getText());
		}
		else if (arg.equals("Cancel")) {
			dispose();
		}
		else return super.action(evt, arg);
		return true;
	}
	
	private TextField prefix;
	
	private spiderframe parent;
}
