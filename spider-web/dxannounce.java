import java.awt.*;

public class dxannounce extends Dialog 
{
	public dxannounce(spiderframe parent, String Call2, 
	                         String Freq, String Remarks, Font font) {
		super(parent, "Dx Announce", true);
		this.parent = parent;
		this.setFont(font);
//		Call2 = "";
//		Freq = "";
//		Remarks = ""; // Make sure that Call2, Freq and Remarks are empty when box is displayed.
		
		Panel p1 = new Panel();
		p1.setLayout(new GridLayout(3,2));
		p1.add(new Label("Call: "));
		p1.add(call2 = new TextField(Call2,6));
		p1.add(new Label("Freq. in khz: "));
		p1.add(freq = new TextField(Freq));
	        p1.add(new Label("Remarks"));
		p1.add(remarks = new TextField(Remarks,15));
        	add("North", p1);
		
		// Panel p3 = new Panel();
		// p3.add(new Label("Remarks"));
		// p3.add(freq = new TextField(Remarks,30));
	        // add("Center",p3);

		Panel p2 = new Panel();
		p2.add(new Button("OK"));
		p2.add(new Button("Cancel"));
		add("South", p2);
		
		resize(250,150);
		
		show();
	}
	
	public boolean action(Event evt, Object arg) {
		if (arg.equals("OK")) {
			dispose();
			parent.setCall2(call2.getText());
			parent.setFreq(freq.getText());
			parent.setRemarks(remarks.getText());
		}

		else if (arg.equals("Cancel")) {
			dispose();
		}
		else return super.action(evt, arg);
		return true;
	}
	
	private TextField call2;
	private TextField freq;
	private TextField remarks;	
	private Font font = new Font("Courier" , Font.PLAIN ,16);
	private spiderframe parent;
}
