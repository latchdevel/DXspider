import java.awt.*;

public class PersonalPreferences extends Dialog 
{
	public PersonalPreferences(spiderframe parent, String Call, 
	                         String Fullname, Font font) {
		super(parent, "Personal Preferences", true);
		this.parent = parent;
		this.setFont(font);
		
		Panel p1 = new Panel();
		p1.setLayout(new GridLayout(2,2));
		p1.add(new Label("Call: "));
		p1.add(call = new TextField(Call, 6));
		p1.add(new Label("Passwort: "));
		p1.add(fullname = new TextField(Fullname));
		add("Center", p1);
		
		Panel p2 = new Panel();
		p2.add(new Button("OK"));
		p2.add(new Button("Cancel"));
		add("South", p2);
		
		resize(250,120);
		show();
	}
	
	public boolean action(Event evt, Object arg) {
		if (arg.equals("OK")) {
			dispose();
			parent.setCall(call.getText());
			parent.setFullname(fullname.getText());
		}
		else if (arg.equals("Cancel")) {
			dispose();
		}
		else return super.action(evt, arg);
		return true;
	}
	
	private TextField call;
	private TextField fullname;
	
	private spiderframe parent;
}
