import java.awt.*;
import java.applet.*;
import java.io.*;
import java.net.*;
import java.util.*;

public class spiderframe extends Frame {


	public spiderframe(spiderclient parent) {
		
		super("Spider DX Cluster");
		this.parent = parent;
		this.setFont(OutFont);

		menubar = new MenuBar();
		file = new Menu("File");
		file.add(connect_menuitem);
		file.add(new MenuItem("About"));
		file.add(new MenuItem("Quit"));
		if (Call.equals("NOCALL")) connect_menuitem.disable();
		menubar.add(file);
		
		edit = new Menu("Edit");
		edit.add(copy_menuitem);
		edit.add(paste_menuitem);
		copy_menuitem.disable();
		paste_menuitem.disable();
menubar.add(edit);
		
		

//		settings = new Menu("Preferences");
//		settings.add(new MenuItem("Personal preferences ..."));
// menubar.add(settings);
		
		
		
		commands = new Menu("Commands");
		commands.add(new MenuItem("Help"));
		commands.add(new MenuItem("Bye"));
menubar.add(commands);
		
		show = new Menu("Show");
		show.add(new MenuItem("Show Last DX"));
		show.add(new MenuItem("Show Beam Direction"));
                            show.add(new MenuItem("Show wwv"));
                            show.add(new MenuItem("Search DX"));
		show.add(new MenuItem("Search Address"));
                            show.add(new MenuItem("Search QSL Manager"));
		show.add(new MenuItem("Search QSL Info"));
		show.add(new MenuItem("Search DXCC"));
		show.add(new MenuItem("Status"));
menubar.add(show);


		set = new Menu("Settings");
		set.add(new MenuItem("Set Beep"));
		set.add(new MenuItem("Set QTH / City"));
		set.add(new MenuItem("Set Name"));
		set.add(new MenuItem("Set Locator"));
		set.add(new MenuItem("Show Personal Settings"));
menubar.add(set); 


		dxann = new Menu("DXannounce");
		dxann.add(new MenuItem("DXannounce"));
menubar.add(dxann);	

		mailbox = new Menu("Mailbox");
		mailbox.add(new MenuItem("Last 50 Msgs"));
		mailbox.add(new MenuItem("List DX Bulletins"));
menubar.add(mailbox); 







		this.setMenuBar(menubar);

		setLayout(new BorderLayout());
		
		Panel p1 = new Panel();
		p1.setLayout(new BorderLayout());
		
		output = new TextArea();
		output.setEditable(false);

		p1.add("Center", output);
		input = new TextArea(2,80);
		input.setEditable(false);
		p1.add("South", input);
		add("Center", p1);
		
		
		Panel p2 = new Panel();
		p2.setLayout(new FlowLayout());
		connectButton.enable();
		p2.add(connectButton);
						
		disconnectButton.disable();
		p2.add(disconnectButton);
		add("South", p2);
		

		Panel p3 = new Panel();
		GridBagLayout gbl = new GridBagLayout();
		p3.setLayout(gbl);
		
		GridBagConstraints gbc = new GridBagConstraints();
		gbc.weightx = 20;
		gbc.weighty = 100;
		gbc.fill = GridBagConstraints.HORIZONTAL;
		gbc.anchor = GridBagConstraints.CENTER;
		
		add(p3,DateLabel,gbl, gbc, 0, 0, 1, 1);
		add(p3,IdleLabel, gbl, gbc, 2, 0, 2, 1);
		add(p3,connectState,gbl, gbc, 4, 0, 2, 1);
		
		add("North",p3);
				
		setColors();
		setFonts();
		
		setDate time = new setDate(this);
		idle = new idleTime(this);
		
	}


	private void add(Panel p,Component c, GridBagLayout gbl,
		GridBagConstraints gbc,
		int x, int y, int w, int h) {
		
		gbc.gridx = x;
		gbc.gridy = y;
		gbc.gridwidth = w;
		gbc.gridheight = h;
		gbl.setConstraints(c, gbc);
		p.add(c);
	}

	public void setColors() {
		output.setBackground(OutBackgroundColor);
		output.setForeground(OutForegroundColor);
		input.setBackground(InBackgroundColor);
		input.setForeground(InForegroundColor);
	}
	
	public void setFonts() {
		output.setFont(OutFont);
		input.setFont(InFont);
	}
	
	public void initPrintStream(PrintStream out) {
		this.out = out;
	}
	
	public void setText(String s) {
		int i;
		
		 for (i=0; i < s.length(); i++) {
			if (s.charAt(i) == '\007')
				parent.beep();
		 }
		output.appendText(s +'\n');
		 idle.resetTimer();
	}
	
	public void setCall(String s) {
		Call = s;
	}

    public void setPassword(String s) {
        Password = s ;
    }

	public void setPrefix(String s) {
	        Prefix = s;
		}
	
	

	public void setCall2(String s) {
	        Call2 = s;
		}
	
      public void setFreq(String s) {
	        Freq = s;
		}
	

      public void setRemarks(String s) {
	        Remarks = s;
		}
	


	
	public void setTime(String s) {
		DateLabel.setText(s);
	}

	public void setIdle(String s) {
		IdleLabel.setText(s);
	}
	
	public String getCall() {
		return Call;
	}
	
    public String getPassword() {
        return Password;
    }
    
	public String setPrefix(){
	       return Prefix;
	       }
	
	public String setCall2(){
	       return Call2;
	       }
	
	public String setFreq(){
	       return Freq;
	       }
	
	public String setRemarks(){
	       return Remarks;
	       }
	
	
	
	
	
	public void setFullname(String s) {
		Fullname = s;
		if (Call.equals("NOCALL")) 
			connect_menuitem.disable();
		else
			connect_menuitem.enable();
	}
	
	public String getFullname() {
		return Fullname;
	}
	
	public void setHostname(String s) {
		Hostname = s;
	}
		
	public String getHostname() {
		return Hostname;
	}
	
	public void setPort(String s) {
		Port = s;
	}
	
	public String getPort() {
		return Port;
	}

	public void setChannel(String s) {
		Channel = s;
	}
	
	public String getChannel() {
		return Channel;
	}
	
//	public void login() {
//		PersonalPreferences pp = new PersonalPreferences(this, Call, Fullname, OutFont);
//	}
	
	public void antrichtung () {
	        beam pp = new beam (this, Prefix,OutFont);
	}
	
		public void dxannounce () {
	        dxannounce pp = new dxannounce (this, Call2, Freq, Remarks, OutFont);
	}
	

	
	
	
		
	public boolean handleEvent(Event evt) {
		if (evt.id == Event.KEY_PRESS) {
			if (evt.key == '\n') {
				
				
				
				idle.resetTimer();
				output.appendText(input.getText()+'\n');
				out.println(input.getText());
						

				if (MaxInputPos < 255) {
					InputPos++;			
					
					MaxInputPos++;
				}
				else {
					for(int i=0; i < 254; i++) {
						InputBuffer[i] = new String(InputBuffer[i+1]);
					}
				 	
                                                         InputPos = 255;
				}
				InputBuffer[InputPos-1] = new String(input.getText());
				input.setText("");
				return true;
			}
		} else if (evt.id == Event.KEY_ACTION) {
			if (evt.key == Event.UP) {
				if (InputPos > 0) {
				 InputPos--;
					input.setText(InputBuffer[InputPos]);
				}
				return true;
			}
			else if (evt.key == Event.DOWN) {
				if (InputPos < MaxInputPos) {
					InputPos++;
					input.setText(InputBuffer[InputPos]);
				}
				else {
					input.setText("");	
				}
				
			} 
			return true;
		}
		
		return super.handleEvent(evt);
	}

	public synchronized void show() {
		move(50, 50);
		super.show();
	}	
	
	public void setUserColor(Color c, String whichColor) {
		if (whichColor.equals("Output Background ...")) {
			OutBackgroundColor = c;
		}
		else if (whichColor.equals("Output Foreground ...")) {
			OutForegroundColor = c;
		} else 	if (whichColor.equals("Input Background ...")) {
			InBackgroundColor = c;
		}
		else if (whichColor.equals("Input Foreground ...")) {
			InForegroundColor = c;
		} else if (whichColor.equals("Output own text ...")) {
			OutOwnColor = c;
		} 

		setColors();
	}
	
	
	public void connected() {
		connect_menuitem.setLabel("Disconnect");
		connectState.setText("Connected to "+Hostname+":"+Port);
		input.setEditable(true);
		copy_menuitem.enable();
		Connected = true;
		connectButton.disable();
		disconnectButton.enable();
	}
	
	public void disconnected() {
		Connected = false;
		connect_menuitem.setLabel("Connect");
		connectState.setText("Disconnected from "+Hostname);
		input.setEditable(false);
		copy_menuitem.disable();
		paste_menuitem.disable();
		connectButton.enable();
		disconnectButton.disable();
	}
	
	public void setUserFont(String name, int size, int style, 
	                        String whichFont) {
		if (whichFont.equals("Area ...")) {
			OutFont = new Font(name, style, size);
		}
		else if (whichFont.equals("Input Line ...")) {
			InFont = new Font(name, style, size);
		}
		
		setFonts();
	}
	
	
	public void getSelectedText() {
		CopyPaste = new String(output.getSelectedText());
		paste_menuitem.enable();
	}
	
	public boolean action(Event evt, Object arg) {
		if (evt.target instanceof MenuItem) {
			if (arg.equals("Quit")) {
				this.hide();
		//	} else if (arg.equals("Personal preferences ...")) {
		//		PersonalPreferences pp = new PersonalPreferences(this,
		//			Call, Fullname, OutFont);
			} else if (arg.equals("Connect")) {
				parent.doconnect();
			} else if (arg.equals("Disconnect")) {
				parent.dodisconnect();
			} else if (arg.equals("About")) {
				InfoDialog id = new InfoDialog(this, "About", 
				"JAVA Spider Webclient 0.6b\nPA4AB\n" +
				"pa4ab@pa4ab.net \n" +
				"April 2001\n" +
				"Based on source of the CLX Client from dl6dbh" );
				
			 id.resize(500,300);
				id.show();
			} else if (arg.equals("Copy")) {
				getSelectedText();
			} else if (arg.equals("Paste")) {
				input.insertText(CopyPaste,input.getSelectionStart());
			} else if (arg.equals("Bye")) {
				if (Connected) out.println("bye");
			} else if (arg.equals("Help")) {
				if (Connected) out.println("help overview");
			} else if (arg.equals("Show Last DX")) {
				if (Connected) out.println("sh/dx");
			} else if (arg.equals("Status")) {
				if (Connected) out.println("sh/conf");
			} else if (arg.equals("Show WWV")) {
				if (Connected) out.println("sh/wwv");
			} else if (arg.equals("Show Beam Direction")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("sh/heading " + Prefix );
			} else if (arg.equals("search DX")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("sh/dx " + Prefix );
			
			} else if (arg.equals("Search QSL Info")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("sh/qsl " + Prefix );
			 

			} else if (arg.equals("search Adress")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("sh/qrz " + Prefix );
			

			} else if (arg.equals("search qsl Manager")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("sh/qsl " + Prefix );
			

			} else if (arg.equals("search DXCC")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("sh/dxcc " + Prefix );
			
			// buttom settings

			} else if (arg.equals("Set Beep")) {
				if (Connected) out.println("set/Beep");
			
			}else if (arg.equals("Set QTH / City")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("set/qth " + Prefix );
			

			}else if (arg.equals("Set Name")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("set/name " + Prefix );
			
			}
			else if (arg.equals("Set Locator")) {
				beam pp = new beam(this, Prefix, OutFont);
			        if (Connected) out.println ("set/loc " + Prefix );
			

			}
			else if (arg.equals("Show Personal Settings")) {
				if (Connected) out.println ("show/sta " + Call );
			

			}

			// dx announce

			else if (arg.equals("DXannounce")) {
				dxannounce pp = new dxannounce(this, Call2, Freq, Remarks, OutFont);
	        		if (Connected) out.println ("dx " + Call2 + " " + Freq + " " + Remarks );
	
			}
			// mailbox 
			 else if (arg.equals("last 50 Msgs")) {
				if (Connected) out.println ("dir/50 " );
			 }
			 else if (arg.equals("list DX Bulletins")) {
				if (Connected) out.println ("dir/bul " );
			 }
			 else if (arg.equals("new Msgs")) {
			 	if (Connected) out.println ("dir/new " );
			 }
			 else if (arg.equals("own Msgs")) {
				if (Connected) out.println ("dir/own " );
			 }
				


			else return false;
		}
		else if (evt.target instanceof Button) {
			if (arg.equals("Connect")) {
				if (!Connected) {
					parent.doconnect();
				} else return false;
			} else if (arg.equals("Disconnect")) {
				if (Connected) {
					parent.dodisconnect();
				} else return false;
			}
		
			else return false;
		}
		
		return true;
	}

	private idleTime idle;

	private TextArea input;
	private TextArea output;
	private MenuBar menubar;
	private Menu file;
	private Menu edit;
	private Menu settings;
	private Menu colors;
	private Menu fonts;
	private Menu commands;
	private Menu show;
	private Menu set;
	private Menu dxann;
	private Menu mailbox;


	private MenuItem connect_menuitem = new MenuItem("Connect");
	private MenuItem copy_menuitem = new MenuItem("Copy");
	private MenuItem paste_menuitem = new MenuItem("Paste");

	private Button connectButton = new java.awt.Button("Connect");
	private Button disconnectButton = new java.awt.Button("Disconnect");

	private Date today = new Date();
	private Label DateLabel = new Label(today.toLocaleString());
	private Label IdleLabel = new Label("00:00");
	private Label connectState = new Label("not connected");
	
 
	private Color OutBackgroundColor = new Color(0,0,66);
	private Color OutForegroundColor = new Color(255,255,0);
	private Color OutOwnColor = Color.red;
	private Color InBackgroundColor = new Color(234,199,135);
	private Color InForegroundColor = Color.red;
	
	private Font OutFont = new Font("Courier", Font.PLAIN, 13);
	private Font InFont = new Font("Courier", Font.BOLD, 13);
	
	private String Call = new String("NOCALL");
	private String Password = new String();
	private String Fullname = new String("NOBODY");
	private String Hostname = new String("localhost");
	private String Port = new String("3600");
	private String Channel = new String("0");


        private String Prefix = new String ("");        
        private String Call2 = new String ("");        
        private String Freq = new String ("");        
        private String Remarks = new String ("");        







	private PrintStream out = null;
	
	private String InputBuffer[] = new String[256];
	private int InputPos = 0;
	private int MaxInputPos = 0;
	
	private String CopyPaste; 
	
	private boolean Connected;
	
	private spiderclient parent;

}

class setDate extends Thread {

	spiderframe cf;
	
	public setDate(spiderframe cf) {
		this.cf = cf;
		this.start();
	}

	public void run() {
		for(;;) {
			try { sleep(1000); } catch (InterruptedException e) {}
			today = new Date();
			cf.setTime(today.toLocaleString());
		}
	}
	
	private Date today = new Date();
	
}


class idleTime extends Thread {

	spiderframe cf;
	int count;
	
	public idleTime(spiderframe cf) {
		this.cf = cf;
		this.start();
		count = 0;
	}

	public void resetTimer() {
		count=0;
	}

	public void run() {
		
		for(;;) {
			try { sleep(1000); } catch (InterruptedException e) {}
			count++;
			String sec = new Format("%02d").form(count % 60);
			String min = new Format("%02d").form(count / 60);
			cf.setIdle("Idle: "+min+":"+sec);
		}
	}
}
