import java.awt.*;

public class InfoDialog extends Dialog {
	protected Button button;
	protected MultiLineLabel label;
	
	
	public InfoDialog(Frame parent, String title, String message) { 
		super(parent, title, false);
	
		this.setLayout(new BorderLayout(15,15));
		label = new MultiLineLabel(message, 20, 20, 1);
		this.add("Center", label);
	
		button = new Button("OK");
		Panel p = new Panel();
		p.setLayout(new FlowLayout(FlowLayout.CENTER, 15, 15));
		p.add(button);
		this.add("South", p);
	
		this.pack();
		this.show();
	}

	public boolean action(Event e, Object arg) {
		if (e.target == button) {
			this.hide();
			this.dispose();
			return true;
		}
		else return false;
	}	
	
	public boolean gotFocus(Event e, Object Arg) {
		button.requestFocus();
		return true;
	}
}
